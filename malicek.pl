#!/usr/bin/perl
# Malíček, an alternative interface for alik.cz.
#
# The goal is to provide a fairly stateless and simple REST interface.
# Malíček only holds Alík's session cookies and issues its own.  It does
# nothing more than translate authenticated requests against relevant
# resources upstream.
#
# Feature overview:
#
#  * Klubovna (partially supported)
#  * Nástěnky (unsupported)
#  * Vizitky (unsupported)
#  * Pošta (unsupported)
#  * Alíkoviny (unsupported)
#  * Vtipy (unsupported)
#  * Hry (Lednička supported)
#
# See public/LICENSE.txt for license and authors.

use strict;
use warnings;
use utf8;
use v5.20;

our $APP = 'Malicek';
use version 0.77; our $VERSION = version->declare('v0.2.0');
our $AGENT = "${APP}/${VERSION}";

use Dancer2;
use File::stat;
use File::Temp qw/:POSIX/;
use HTML::Entities;
use HTTP::Cookies;
use LWP::UserAgent;

set serializer => 'JSON';
set session => 'Simple';

my $alik = 'https://www.alik.cz';

{
    package Malicek::Room;
    use Mo qw/default xs/;
    has 'name';
    has 'id';
    has 'topic';
    has 'creator';
    has 'allowed' => 'all';
    has 'users' => [];
    has 'messages' => [];
    sub dump {
        my $self = shift;
        return {
            name => $self->name,
            id => $self->id,
            topic => $self->topic,
            creator => $self->creator,
            allowed => $self->allowed,
            users => [ map { $_->dump } $self->users->@* ],
            messages => [ map { $_->dump } $self->messages->@* ],
        }
    }
}

{
    package Malicek::User;
    use Mo qw/default xs/;
    has 'name';
    has 'id';
    has 'link';
    has 'age';
    has 'sex' => 'unisex';
    has 'avatar';
    has 'admin' => [];
    has 'since';
    has 'last';
    sub dump {
        my $self = shift;
        return {
            name => $self->name,
            id => $self->id,
            link => $self->link,
            age => $self->age,
            sex => $self->sex,
            avatar => 'https://' . $self->avatar,
            admin => $self->admin,
            since => $self->since,
            last => $self->last,
        }
    }
}

{
    package Malicek::Profile;
    use Mo qw/default xs/;
    extends 'Malicek::User';
    has 'realname';
    has 'home';
    has 'hobbies';
    has 'rank';
    has 'registered';
    has 'quest';
    has 'likes';
    has 'dislikes';
    has 'pictures' => [];
    has 'style';
    has 'counter';
    has 'visitors';
    sub dump {
        my $self = shift;
        return {};
    }
}

{
    package Malicek::Message;
    use Mo qw/default xs/;
    has 'type';
    has 'event';
    has 'from';
    has 'to';
    has 'message';
    has 'color';
    has 'time';
    has 'avatar';
    sub dump {
        my $self = shift;
        return {
            type => $self->type,
            event => $self->event ? $self->event->dump : undef,
            from => $self->from,
            to => $self->to,
            message => $self->message,
            time => $self->time,
            avatar => $self->avatar,
            color => $self->color,
        };
    }
}

{
    package Malicek::Event;
    use Mo qw/default xs/;
    has 'type';
    has 'source';
    has 'target';
    sub dump {
        my $self = shift;
        return {
            type => $self->type,
            source => $self->source,
            target => $self->target,
        }
    }
}

{
    package Malicek::Settings;
    use Mo qw/default xs/;
    has 'avatars';
    has 'colors';
    has 'highlight';
    has 'system';
    has 'time';
    has 'color';
    has 'refresh';
    sub dump {
        my $self = shift;
        return {
            avatars => $self->avatars ? \1 : \0,
            colors => $self->colors ? \1 : \0,
            highlight => $self->highlight ? \1 : \0,
            system => $self->system ? \1 : \0,
            time => $self->time ? \1 : \0,
            color => $self->color,
            refresh => int($self->refresh),
        };
    }
}

{
    package Malicek::Game::Lednicka;
    use Mo qw/default xs/;
    has 'active';
    has 'defrost';
    has 'total';
    has additions => [];
    sub dump {
        my $self = shift;
        return {
            active => $self->active,
            defrost => $self->defrost,
            total => $self->total,
            additions => [ map { $_->dump } $self->additions->@* ],
        };
    }
}

{
    package Malicek::Game::Lednicka::Addition;
    use Mo qw/default xs/;
    has 'who';
    has 'when';
    has 'method';
    has 'amount';
    sub dump {
        my $self = shift;
        return {
            who => $self->who,
            when => $self->when,
            method => $self->method,
            amount => int($self->amount),
        };
    };
}

sub login {
    my ($user, $pass) = @_;
    my $ua = LWP::UserAgent->new(
        cookie_jar => {},
        agent => $AGENT,
        keep_alive => 1,
        max_redirect => 0,
    );
    my $r = $ua->post(
        "${alik}/prihlasit",
        [
            login => $user,
            heslo => $pass,
            typ => 'login_alik',
            pamatovat => 'on',
        ],
    );
    if ($r->is_redirect()) {
        return $ua;
    } else {
        return undef;
    }
}

sub logout {
    if (session('cookies')) {
        unlink session('cookies')
            if -f session('cookies');
        app->destroy_session;
    }
}

sub reconcile {
    if ($_[0] =~ /
        <a\shref="\/prihlasit[^"]*"\sclass="[^"]+">Přihlásit<\/a>
        /sx) {
        logout();
        return 0;
    }
    return 1;
}

sub load_cookies {
    return session('cookies')
        ? HTTP::Cookies->new(
            file => session('cookies'),
            autosave => 0,
        )
        : HTTP::Cookies->new();
}

sub save_cookies {
    session('ua')->cookie_jar->save(session('cookies'));
}

sub sanitize {
    return $_[0] =~ s/\s+/ /sgr;
}

sub parse_status {
    $_[0] =~ /
        ^Alik\.pocty\(
        "(?<mail>\d+)",\s
        "(?<people>\d+)!?",\s
        "(?<cash>[0-9\s]+)"\);$/sx;
    return {
        mail => int($+{mail}),
        people => int($+{people}),
        cash => int($+{cash} =~ s/\s+//gr),
    };
}

sub parse_rooms {
    my @rooms = ();
    while ($_[0] =~ /
        <li>\s+<div\sclass="klubovna-stul(?>\sklubovna-zamek\sklubovna-zamek-
        (?<lock>cerveny|zeleny|modry|zluty))?">\s+
        (?><a\shref="\/k\/(?<id>[^"]+)"\sclass="sublink\sstul-nazev">
        |<i\sclass="stul-nazev">)<u>(?<name>[^<]+)<\/u>
        (?>\s+<small>–\s(?<topic>[^<]+)<\/small>)?<\/[ai]>
        (?><small\sclass=fr>\(založila?\s<a\shref="\/u\/[^"]+">
        <span>(?<creator>[^<]+)<\/span><\/a>\)<\/small>)?\s+<\/div>\s+
        (?><div\sclass="klubovna-lidi"\sdata-pocet="\d+">
        (?<people>.+?)<\/div>)?
        /sgx) {
        my $room = Malicek::Room->new(
            name => $+{name},
        );
        $room->id($+{id})
            if defined($+{id});
        $room->creator($+{creator})
            if defined($+{creator});
        $room->topic($+{topic})
            if defined($+{topic});
        if (defined($+{lock})) {
            if ($+{lock} eq 'zluty') {
                $room->allowed('none');
            } elsif ($+{lock} eq 'cerveny') {
                $room->allowed('boys');
            } elsif ($+{lock} eq 'modry') {
                $room->allowed('girls');
            } elsif ($+{lock} eq 'zeleny') {
                $room->allowed('friends');
            }
        }
        my $people = $+{people};
        while ($people =~ /
            <a\shref="\/u\/(?<link>[^"]+)"\sclass="sublink
            (?>\sklubovna-(?<sex>kluk|holka))?">
            (?><img\ssrc="\/\/(?<avatar>[^"]+)">)?<u>
            <span(?>\sclass="(?<admin>[^"]+)"\stitle="[^"]+")?>
            (?<name>[^<]+)<\/span><\/u><span\sclass="klubovna-info">
            (?>(?<age>\d+)\slet|dítě|dospěl[ýá])<\/span><\/a>
            /sgx) {
            my $user = Malicek::User->new(
                name => $+{name},
                link => $+{link},
            );
            $user->age($+{age})
                if defined($+{age});
            if (defined($+{sex})) {
                if ($+{sex} eq 'kluk') {
                    $user->sex('boy');
                } else {
                    $user->sex('girl');
                }
            }
            $user->avatar($+{avatar})
                if defined($+{avatar});
            if (defined($+{admin})) {
                my $admin = $+{admin};
                if ($admin eq 'uzivatel-podspravce') {
                    push $user->admin->@*, 'chat';
                } else {
                    if ($admin =~ /uzivatel-zverolekar/) {
                        push $user->admin->@*, 'guru';
                    }
                    if ($admin =~ /uzivatel-spravce/) {
                        push $user->admin->@*, 'master';
                    }
                    if ($admin =~ /uzivatel-podspravce-\d\d1/) {
                        push $user->admin->@*, 'boards';
                    }
                    if ($admin =~ /uzivatel-podspravce-\d1\d/) {
                        push $user->admin->@*, 'rooms';
                    }
                    if ($admin =~ /uzivatel-podspravce-1\d\d/) {
                        push $user->admin->@*, 'blog';
                    }
                }
            }
            push $room->users->@*, $user;
        }
        push @rooms, $room->dump;
    }
    return \@rooms;
}

sub parse_chat {
    my (%users, @messages);
    $_[0] =~ /
        <!--reload\("zamceno"\)-->(?<lock>.*)<!--\/reload-->.*
        Stůl:\s(?<name>[^<]+)<small\sid="bleskopopisek">
        <!--reload\("bleskopopisek"\)-->(?<topic>[^<]*)<!--\/reload-->
        <\/small><\/h2><p>
        Stůl\szaložil\/a:\s<a\shref="\/u\/[^"]+">(?<creator>[^<]+)<\/a>
        /sx;
    my $room = Malicek::Room->new(
        name => $+{name},
        topic => $+{topic},
        creator => $+{creator},
    );
    if ($+{lock}) {
        if (index($+{lock}, 'lock.png') != -1) {
            $room->allowed('none');
        } elsif (index($+{lock}, 'lockh.png') != -1) {
            $room->allowed('boys');
        } elsif (index($+{lock}, 'lockk.png') != -1) {
            $room->allowed('girls');
        } elsif (index($+{lock}, 'locknf.png') != -1) {
            $room->allowed('friends');
        } else {
            $room->allowed('unknown');
        }
    }
    while ($_[0] =~ /
        <option\svalue="(?<id>\d+)">(?<name>.+?)<\/option>
        /sgx) {
        next if $+{id} == 0;
        $users{$+{name}} = Malicek::User->new(
            name => $+{name},
            id => $+{id},
        );
    }
    while ($_[0] =~ /
        (<span\sclass="(?<admin>guru|master|super[nkr]{1,3}|chef)"><\/span>)?
        <h4\sclass="(?<sex>boy|girl|unisex)">
        (?<nick>[^<]+)<\/h4>
        <div\sclass="user-status">
        (<p>Je\smi:\s<b>(?<age>\d+)\s+[^<]+<\/b><\/p>)?
        .+?href="\/u\/(?<link>[^"]+)"\sclass="vizitka"
        .+?od\s(?<since>[^<]+)<\/b>.+?
        Poslední\szpráva:\s<b>(?<last>[^<]+)<\/b>
        /sgx) {
        $users{$+{nick}} //= Malicek::User->new(name => $+{nick});
        $users{$+{nick}}->link($+{link});
        $users{$+{nick}}->sex($+{sex});
        $users{$+{nick}}->since($+{since});
        $users{$+{nick}}->last($+{last});
        $users{$+{nick}}->age($+{age}) if $+{age};
        if ($+{admin}) {
            my ($admin, $nick, @admin) = ($+{admin}, $+{nick});
            if ($admin eq 'chef') {
                push @admin, 'chat';
            } elsif ($admin =~ /^super/) {
                push @admin, 'rooms' if $admin =~ /^super.*k.*$/;
                push @admin, 'boards' if $admin =~ /^super.*n.*$/;
                push @admin, 'blog' if $admin =~ /^super.*r.*$/;
            } elsif ($admin =~ /^(?>master|guru)$/) {
                push @admin, $admin;
            } else {
                @admin = ();
            }
            $users{$nick}->admin([ @admin ]);
        }
    }
    $room->users([ values %users ]);
    while ($_[0] =~ /
        <p\sclass="(?<type>system|c-1)">
        (?><span\sclass="time">(?<time>\d{1,2}:\d{2}:\d{2})<\/span>)?
        (?><img\s[^\/]+\/\/(?<avatar>[^"]+)">)?
        \s+
        (?<message>.+?)<\/p>
        /sgx) {
        my $msg = Malicek::Message->new();
        $msg->type($+{type} eq 'system' ? 'system' : 'chat');
        $msg->time(length($+{time}) == 8 ? $+{time} : '0' . $+{time})
            if $+{time};
        $msg->avatar('https://' . $+{avatar})
            if $+{avatar};
        if ($+{type} eq 'system') {
            $msg->message($+{message} =~ s/<[^>]+>|\s+$//sgxr);
            if ($msg->message() =~ /^Kamarád(?>ka)? (?<nick>.+) si přisedla? ke stolu\.$/) {
                $msg->event(Malicek::Event->new(
                    type => 'join',
                    source => $+{nick},
                ));
            } elsif ($msg->message() =~ /^Kamarád(?>ka)? (?<nick>.+) (?>vstala? od|přeš(?>el|la) k jinému) stolu\.$/) {
                $msg->event(Malicek::Event->new(
                    type => 'part',
                    source => $+{nick},
                ));
            } elsif ($msg->message() =~ /^Alík odebral kamarád(?>ovi|ce) (?<nick>.+) místo u stolu z důvodu neaktivity.$/) {
                $msg->event(Malicek::Event->new(
                    type => 'part',
                    source => $+{nick},
                ));
            } elsif ($msg->message() =~ /^Kamarád(?>ka)? (?<nick>.+) zamkla? stůl/) {
                $msg->event(Malicek::Event->new(
                    type => 'lock',
                    source => $+{nick},
                ));
            } elsif ($msg->message() =~ /^Kamarád(?>ka)? (?<nick>.+) odemkla? stůl/) {
                $msg->event(Malicek::Event->new(
                    type => 'unlock',
                    source => $+{nick},
                ));
            } elsif ($msg->message() =~ /^Kamarád(?>ka)? (?<nick>.+) vyčistila? stůl\.$/) {
                $msg->event(Malicek::Event->new(
                    type => 'clear',
                    source => $+{nick},
                ));
            } elsif ($msg->message() =~ /^Kamarád(?>ka)? (?<nick>.+) byla? vyhozena? správcem od stolu\.$/) {
                $msg->event(Malicek::Event->new(
                    type => 'kick',
                    target => $+{nick},
                ));
            } elsif ($msg->message() =~ /^Kamarád(?>ka)? (?<nick>.+) předala? správce\.$/) {
                $msg->event(Malicek::Event->new(
                    type => 'oper',
                    source => $+{nick},
                ));
            } else {
                $msg->event(Malicek::Event->new(
                    type => 'unknown',
                ));
            }
        } else {
            $+{message} =~ /
                (?<private><span\sclass="septani"><\/span>)?
                <font\scolor="(?>(?<color>\#[a-fA-F0-9]{6})|[^"]+)">
                <strong>(?<nick>[^<]+)<\/strong>
                (\s⇨\s(?><em>)?(?<to>[^<]*)(?><\/em>)?)?
                :\s(?<msg>.+?)<\/font>
                /sgx;
            my $private = $+{private};
            $msg->color($+{color})
                if $+{color};
            $msg->from($+{nick});
            $msg->to($+{to})
                if $private;
            my $raw = $+{msg};
            $raw =~ s/<img\sclass="smiley"\ssrc="[^"]+"\salt="([^"]+)">?/[$1]/sgx;
            # Workaround for broken highlights in links
            $raw =~ s/<\/?em>//sgx;
            $raw =~ s/<[^>]*>//sgx;
            $msg->message(decode_entities($raw));
            undef $msg if $private && ! $msg->to;
        }
        push @messages, $msg if $msg;
    }
    $room->messages(\@messages);
    return $room->dump;
}

sub parse_settings {
    $_[0] =~ /
        \sname="system"(?<system>\schecked)?
        .*name="barvy"(?<colors>\schecked)?
        .*name="cas"(?<time>\schecked)?
        .*name="ikony"(?<avatars>\schecked)?
        .*value="(?<refresh>\d+)"\sselected
        .*name="highlight"(?<highlight>\schecked)?
        .*name="barva"\svalue="(?<color>\#[a-fA-F0-9]{6})"
         /sgx;
    return Malicek::Settings->new(
        avatars => $+{avatars},
        colors => $+{colors},
        highlight => $+{highlight},
        system => $+{system},
        time => $+{time},
        color => $+{color},
        refresh => int($+{refresh}),
    )->dump;
}

sub get_status {
    my $r = session('ua')->get(
        "${alik}/-/online"
    );
    redirect('/')
        unless $r->decoded_content();
    return parse_status(sanitize($r->decoded_content()));
}

hook before => sub {
    if (session('cookies')) {
        session ua => LWP::UserAgent->new(
            agent => $AGENT,
            cookie_jar => load_cookies(),
            keep_alive => 1,
            max_redirect => 0,
        )
            unless session('ua');
    } else {
        forward '/'
            unless request->path =~ /^\/(?>login)?$/;
    }
};

hook after => sub {
    save_cookies()
        if session('cookies');
};

get '/' => sub {
    my %selfid = (
        app => $APP,
        version => $VERSION->stringify(),
        agent => $AGENT,
    );
    if (session('cookies')) {
        return {
            %selfid,
            state => \1
        };
    } else {
        status(401);
        return {
            %selfid,
            state => \0
        };
    }
};

post '/login' => sub {
    my ($user, $pass) = (
        body_parameters->get('user'),
        body_parameters->get('pass'),
    );
    my $ua = login($user, $pass);
    if ($ua) {
        session cookies => (tmpnam())[1];
        session ua => $ua;
        save_cookies();
    } else {
        logout();
    }
    redirect('/');
};

get '/logout' => sub {
    session('ua')->get(
        "$alik/odhlasit",
    );
    logout();
    redirect('/');
};

get '/status' => sub {
    return get_status();
};

get '/rooms' => sub {
    my $r = session('ua')->get(
        "${alik}/k",
    );
    redirect('/')
        unless reconcile($r->decoded_content());
    return parse_rooms(sanitize($r->decoded_content()));
};

# TODO: Figure out how to determine we were kicked out for
# inactivity without autorejoining the room.
get '/rooms/:id' => sub {
    my ($r, $f);
    if (query_parameters->get('query')
        && query_parameters->get('query') eq 'settings') {
        $f = \&parse_settings;
        $r = session('ua')->get(
            "${alik}/k/" . route_parameters->get('id') . '/nastaveni',
        );
    } else {
        $f = \&parse_chat;
        $r = session('ua')->get(
            "${alik}/k/" . route_parameters->get('id'),
        );
    }
    redirect('/')
        unless reconcile($r->decoded_content());
    if ($r->code == 302) {
        if ($r->header('Location') =~ /err=(?<err>\d+)/) {
            status(403);
            return {
                error => int($+{err})
            };
        } elsif ($r->header('Location') eq '/k/') {
            session('ua')->get(
                "${alik}/k/" . route_parameters->get('id') . '/odejit',
                Referer => "${alik}/k/" . route_parameters->get('id'),
            );
            if (query_parameters->get('query')) {
                # How did we get here?
                status(501);
                return {
                    error => 501
                };
            } else {
                $r = session('ua')->get(
                    "${alik}/k/" . route_parameters->get('id'),
                );
            }
        }
    }
    return &{$f}(sanitize($r->decoded_content()));
};

post '/rooms/:id' => sub {
    my $action = body_parameters->get('action');
    if ($action eq 'leave') {
        session('ua')->get(
            "${alik}/k/" . route_parameters->get('id') . '/odejit',
            Referer => "${alik}/k/" . route_parameters->get('id'),
        );
        redirect('/rooms');
    } elsif ($action eq 'post') {
        session('ua')->post(
            "${alik}/k/" . route_parameters->get('id'),
            {
                text => body_parameters->get('message'),
                prijemce => body_parameters->get('to') // 0,
                barva => body_parameters->get('color'),
            },
        );
        redirect('/rooms/' . route_parameters->get('id'));
    } else {
        redirect('/rooms/' . route_parameters->get('id'));
    }
};

get '/app' => sub {
    redirect '/app/';
};

get '/app/:file?' => sub {
    my $file = route_parameters->get('file') // 'malicek.html';
    send_file($file);
};

sub game_lednicka {
    my $r = $_[0] // undef;
    unless ($r) {
        $r = session('ua')->get(
            "${alik}/-/lednicka",
        );
    }
    my $page = sanitize($r->decoded_content());
    if ($page =~ /Nejsi\spřihlášen/sx) {
        logout();
        redirect('/');
    }
    my $fridge = Malicek::Game::Lednicka->new(
        active =>
            $page !~/Je\spřičteno!/sx
            || 0,
        total =>
            ($page =~ /<a\shref="\/-\/lednicka".+?>\s+([0-9\s]+)</sx)[0]
            =~ s/\s+//sgr,
    );
    $fridge->defrost($fridge->active ? ($page !~ /onclick="alert/sx || 0) : 0);
    $fridge->defrost($page =~ /Odmrazení\sčtyřčíslí/sx ? 4 : 3)
        if $fridge->defrost;
    while ($page =~ /
        <tr\stitle="(?<when>[^"]+)"><td><a\shref="[^"]+"\starget="_parent">
        (?<who>[^<]+)<\/a>\spřičetla?\s(?<method>[^<]+)
        <td\sstyle="color:\srgb\(\d+,\s\d+,\s\d+\)">(?<amount>[^<]+)/sgx) {
        my $addition = Malicek::Game::Lednicka::Addition->new(
            who => $+{who},
            when => $+{when},
            method => $+{method},
            amount => $+{amount},
        );
        $addition->amount($addition->amount =~ s/\+|\s+//sgr);
        $addition->amount($addition->amount =~ s/&minus;/-/r);
        push $fridge->additions->@*, $addition;
    }
    return $fridge->dump;
}

get '/games/:game' => sub {
    if (route_parameters->get('game') eq 'lednicka') {
        return game_lednicka();
    }
    status(400);
    return {};
};

post '/games/:game' => sub {
    if (route_parameters->get('game') eq 'lednicka') {
        my $method;
        if (query_parameters->get('method')) {
            $method = query_parameters->get('method');
        } else {
            my $fridge = game_lednicka();
            unless ($fridge->{active}) {
                status(409);
                return {};
            }
            my $factor = 10 ** $fridge->{defrost} if $fridge->{defrost};
            my $defrost = $fridge->{defrost}
                ? ((int($fridge->{total} / $factor) + 1) * $factor) - $fridge->{total}
                : 0;
            my ($one, $c) = (0, 1.01);
            map { $c -= 0.01; $one += $c * $_->{amount} } @{$fridge->{additions}};
            $one = int($one / 100);
            my $status = get_status();
            my @time = localtime(); $time[2] = 0 if $time[2] == 24;
            my %methods = (
                1 => $one,
                h => $time[2] * 3,
                m => $time[1],
                M => ($time[4] + 1) * 5,
                d => $time[3] * 2,
                k => int($status->{cash} / 2000),
                c => $status->{people} * 3,
                r => 120,
                o => $defrost
            );
            $method = (sort { $methods{$a} <=> $methods{$b} } keys %methods)[-1];
        }
        return game_lednicka(
            session('ua')->post(
                "${alik}/-/lednicka",
                [
                    pricti => $method,
                ]
            ),
        );
    }
    status(400);
    return {};
};

start;
