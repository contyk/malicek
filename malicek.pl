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
    has 'online' => 1;
    has 'since';
    has 'last';
    sub dump {
        my $self = shift;
        return {
            name => $self->name,
            id => $self->id ? int($self->id) : undef,
            link => $self->link,
            age => $self->age ? int($self->age) : undef,
            sex => $self->sex,
            avatar => $self->avatar,
            admin => $self->admin,
            online => $self->online ? \1 : \0,
            since => $self->since,
            last => $self->last,
        }
    }
}

{
    package Malicek::Profile;
    use Mo qw/default xs/;
    extends 'Malicek::User';
    has 'blocked' => 0;
    has 'gone' => 0;
    has 'rank';
    has 'realname';
    has 'home';
    has 'registered';
    has 'seen';
    has 'hobbies' => [];
    has 'quest';
    has 'likes';
    has 'dislikes';
    has 'pictures' => [];
    has 'style';
    has 'counter';
    has 'visitors' => [];
    # TODO: Two friends lists
    # TODO: Blog posts
    # TODO: Created boards, faved boards
    # TODO: Faved games
    sub dump {
        my $self = shift;
        return {
            $self->SUPER::dump->%*,
            blocked => $self->blocked ? \1 : \0,
            gone => $self->gone ? \1 : \0,
            rank => $self->rank,
            realname => $self->realname,
            home => $self->home,
            registered => $self->registered,
            hobbies => $self->hobbies,
            seen => $self->seen,
            quest => $self->quest,
            likes => $self->likes,
            dislikes => $self->dislikes,
            pictures => $self->pictures,
            style => $self->style,
            counter => $self->counter ? int($self->counter) : undef,
            visitors => $self->visitrs,
        };
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
            color => $self->color,
            time => $self->time,
            avatar => $self->avatar,
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
            refresh => $self->refresh ? int($self->refresh) : undef,
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
    if ($r->is_redirect) {
        return $ua;
    } else {
        return false;
    }
}

sub logout {
    if (session('cookies')) {
        unlink session('cookies')
            if -f session('cookies');
        app->destroy_session;
    }
}

sub badrequest {
    status(400);
    halt({
        status => 400,
        reason => 'Bad request',
    });
}

sub unauthenticated {
    logout;
    status(401);
    halt({
        status => 401,
        reason => 'Unauthorized',
    });
}

sub reconcile {
    if ($_[0] =~ /
        <a\shref="\/prihlasit[^"]*"\sclass="[^"]+">Přihlásit<\/a>
        /sx) {
        unauthenticated;
    }
    return true;
}

sub load_cookies {
    return session('cookies')
        ? HTTP::Cookies->new(
            file => session('cookies'),
            autosave => 0,
        )
        : HTTP::Cookies->new;
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
        "[!?]?(?<people>\d*)[!?]?",\s
        "(?<cash>[0-9\s]+)".*?\);$/sx;
    return {
        mail => int($+{mail}),
        people => int($+{people} || 0),
        cash => int($+{cash} =~ s/\s//gr),
    };
}

sub parse_rooms {
    my @rooms = ();
    while ($_[0] =~ /
        <li>\s<div\sclass="klubovna-stul(?>\sklubovna-zamek\sklubovna-zamek-
        (?<lock>cerveny|zeleny|modry|zluty))?">\s
        (?><a\shref="\/k\/(?<id>[^"]+)"\sclass="sublink\sstul-nazev"[^>]*>
        |<i\sclass="stul-nazev">)<u>(?<name>[^<]+)<\/u>
        (?>\s<small>(?>–\s(?<topic>[^<]+)|\(ticho[^)]*\))<\/small>)?<\/[ai]>
        (?><small\sclass=fr>(?>\(založila?\s<a\shref="\/u\/[^"]+"><span[^>]*>
        (?<creator>[^<]+)<\/span><\/a>\)|<a\shref="\/u\/[^"]+">
        <span\s[^>]+>[^<]+<\/span><samp\s[^>]+><\/samp><\/a>|
        <i\s[^>]+>\(nikdo\)<\/i>)<\/small>)?
        \s<\/div>\s(?><div\sclass="klubovna-lidi(?>\s[^"]+)?"\sdata-pocet="\d+">
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
        while ($people && $people =~ /
            <a\shref="\/u\/(?<link>[^"]+)"\sclass="sublink
            (?>\sklubovna-(?<sex>kluk|holka))?">
            (?><img\ssrc="(?<avatar>[^"]+)">)?<u>
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
            if (defined($+{avatar})) {
                $user->avatar($alik . $+{avatar})
                    if substr($+{avatar}, 0, 2) eq '/-';
                $user->avatar('https:' . $+{avatar})
                    if substr($+{avatar}, 0, 2) eq '//';
            }
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
        <h2\s[^>]+><span\sid="zamceno"><!--reload\("zamceno"\)-->
        (?><img\salt="[^"]+"\ssrc="[^"]+?(?<lock>lock[^.]*)\.png">)?
        <!--\/reload--><\/span>\sStůl:\s(?<name>[^<]+)
        <small\sid="bleskopopisek"><!--reload\("bleskopopisek"\)-->
        (?<topic>[^<]*)<!--\/reload--><\/small><\/h2><p>
        Stůl\szaložil\/a:\s<a\s[^>]+>(?<creator>[^<]+)<\/a>
        /sx;
    my $room = Malicek::Room->new(
        name => $+{name},
        topic => $+{topic},
        creator => $+{creator},
    );
    if ($+{lock}) {
        if ($+{lock} eq 'lock') {
            $room->allowed('none');
        } elsif ($+{lock} eq 'lockh') {
            $room->allowed('boys');
        } elsif ($+{lock} eq 'lockk') {
            $room->allowed('girls');
        } elsif ($+{lock} eq 'locknf') {
            $room->allowed('friends');
        } else {
            $room->allowed('unknown');
        }
    }
    while ($_[0] =~ /
        <li>(?><span\sclass="(?<admin>guru|master|super[nkr]{1,3}|chef)">
        <\/span>)?<h4\sclass="(?<sex>boy|girl|unisex)">(?<nick>[^<]+)<\/h4>
        <div\sclass="user-status">(?><p>Je\smi:\s<b>(?<age>\d+)\s[^<]+<\/b>
        <\/p>)?<ul><li><a\shref="\/u\/(?<link>[^"]+)"\sclass="vizitka"[^>]*>Vizitka
        <\/a><\/li>(?><li><a\s[^.]+\.value\s=\s'(?<id>\d+)'[^>]+>[^<]+<\/a>
        <\/li>)?<\/ul><p>\sU\sstolu\sjsem:\s<b\s[^>]+>od\s(?<since>[^<]+)
        <\/b><br>\sPoslední\szpráva:\s<b>(?<last>[^<]+)<\/b><\/p><\/div><\/li>
        /sgx) {
        my $user = Malicek::User->new(
            name => $+{nick},
            id => $+{id} // undef,
            link => $+{link},
            age => $+{age} // undef,
            sex => $+{sex},
            since => $+{since},
            last => $+{last},
        );
        if (defined($+{admin})) {
            my $admin = $+{admin};
            if ($admin eq 'chef') {
                push $user->admin->@*, 'chat';
            } elsif ($admin =~ /^super/) {
                push $user->admin->@*, 'rooms'
                    if $admin =~ /^super.*k.*$/;
                push $user->admin->@*, 'boards'
                    if $admin =~ /^super.*n.*$/;
                push $user->admin->@*, 'blog'
                    if $admin =~ /^super.*r.*$/;
            } elsif ($admin =~ /^(?>master|guru)$/) {
                push $user->admin->@*, $admin;
            }
        }
        push $room->users->@*, $user;
    }
    while ($_[0] =~ /
        <p\sclass="(?<type>system|c-1)">
        (?><span\sclass="time">(?<time>\d{1,2}:\d{2}:\d{2})<\/span>)?
        (?><img\s[^\/]+(?<avatar>[^"]+)">)?(?<message>.+?)<\/p>
        /sgx) {
        my $msg = Malicek::Message->new;
        $msg->type($+{type} eq 'system' ? 'system' : 'chat');
        $msg->time(length($+{time}) == 8 ? $+{time} : '0' . $+{time})
            if defined($+{time});
        if (defined($+{avatar})) {
            $msg->avatar($alik . $+{avatar})
                if substr($+{avatar}, 0, 2) eq '/-';
            $msg->avatar('https:' . $+{avatar})
                if substr($+{avatar}, 0, 2) eq '//';
        }
        if ($+{type} eq 'system') {
            $msg->message($+{message} =~ s/^\s|<[^>]+>|\s$//sgxr);
            if ($msg->message =~ /^Kamarád(?>ka)? (?<nick>.+) si přisedla? ke stolu\.$/) {
                $msg->event(Malicek::Event->new(
                    type => 'join',
                    source => $+{nick},
                ));
            } elsif ($msg->message =~ /^Kamarád(?>ka)? (?<nick>.+) (?>vstala? od|přeš(?>el|la) k jinému) stolu\.$/) {
                $msg->event(Malicek::Event->new(
                    type => 'part',
                    source => $+{nick},
                ));
            } elsif ($msg->message =~ /^Alík odebral kamarád(?>ovi|ce) (?<nick>.+) místo u stolu z důvodu neaktivity.$/) {
                $msg->event(Malicek::Event->new(
                    type => 'part',
                    source => $+{nick},
                ));
            } elsif ($msg->message =~ /^Kamarád(?>ka)? (?<nick>.+) zamkla? stůl/) {
                $msg->event(Malicek::Event->new(
                    type => 'lock',
                    source => $+{nick},
                ));
            } elsif ($msg->message =~ /^Kamarád(?>ka)? (?<nick>.+) odemkla? stůl/) {
                $msg->event(Malicek::Event->new(
                    type => 'unlock',
                    source => $+{nick},
                ));
            } elsif ($msg->message =~ /^Kamarád(?>ka)? (?<nick>.+) vyčistila? stůl\.$/) {
                $msg->event(Malicek::Event->new(
                    type => 'clear',
                    source => $+{nick},
                ));
            } elsif ($msg->message =~ /^Kamarád(?>ka)? (?<nick>.+) byla? vyhozena? správcem či moderátorem od stolu\.$/) {
                $msg->event(Malicek::Event->new(
                    type => 'kick',
                    target => $+{nick},
                ));
            } elsif ($msg->message =~ /^Kamarád(?>ka)? (?<nick>.+) (?>předal|odebral)a? titul moderátora\.$/) {
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
                ^(?>\s|<span\sclass="b"><span\sclass="septani"><\/span>)
                <font\scolor="(?>(?<color>\#[a-fA-F0-9]{6})|[^"]+)">
                <strong>(?<nick>[^<]+)<\/strong>
                (?>\s(?<private>⇨)\s(?><em>)?(?<to>[^:<]*)(?><\/em>)?)?
                :\s(?<msg>.+?)<\/font>(?><\/span>)?$
                /sx;
            next
                if $+{private} && ! $+{to};
            $msg->color($+{color})
                if $+{color};
            $msg->from($+{nick});
            $msg->to($+{to})
                if $+{private};
            my $raw = $+{msg};
            $raw =~ s/<img\sclass="smiley"\ssrc="[^"]+"\salt="([^"]+)">?/[$1]/sgx;
            # Workaround for broken highlights in links
            $raw =~ s/<\/?em>//sgx;
            $raw =~ s/<a\s+href="([^"]+)"[^>]*>[^<]+<\/a>/$1/sgx;
            $raw =~ s/<[^>]*>//sgx;
            $msg->message(decode_entities($raw));
        }
        push @messages, $msg;
    }
    $room->messages(\@messages);
    return $room->dump;
}

sub parse_settings {
    $_[0] =~ /
        <label><input\stype="checkbox"\svalue="1"\sname="system"
        (?<system>\schecked)?>[^<]+<\/label>
        <label><input\stype="checkbox"\svalue="1"\sname="barvy"
        (?<colors>\schecked)?>[^<]+<\/label>
        <label><input\stype="checkbox"\svalue="1"\sname="cas"
        (?<time>\schecked)?>[^<]+<\/label>
        <label><input\stype="checkbox"\svalue="1"\sname="ikony"
        (?<avatars>\schecked)?>[^<]+<\/label>
        <\/div><div\sclass="half-r">
        <label>[^<]+<select\sname="obnovit">
        (?><option\svalue="(?:\d+"|(?<refresh>\d+)"\sselected)>
        [^<]+<\/option>)+<\/select><\/label>
        <label\sstyle="display:\snone">[^<]+<select\sname="radku">
        (?><option\svalue="\d+">[^<]+<\/option>)+<\/select><\/label>
        <label><input\stype="checkbox"\svalue="1"\sname="highlight"
        (?<highlight>\schecked)?>[^<]+<\/label>
        <label>[^<]+<input\stype="text"\sname="barva"\svalue="
        (?<color>[^"]+)"\ssize="6"\smaxlength="7">
        /sx;
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
    if ($r->decoded_content) {
        return parse_status(sanitize($r->decoded_content));
    }
    unauthenticated;
}

hook before => sub {
    if (session('cookies')) {
        session ua => LWP::UserAgent->new(
            agent => $AGENT,
            cookie_jar => load_cookies,
            keep_alive => 1,
            max_redirect => 0,
        )
            unless session('ua');
    } else {
        if (request->path !~ /^\/(?>malicek|login)?$/) {
            unauthenticated;
        }
    }
};

hook after => sub {
    save_cookies
        if session('cookies');
    response_header('Cache-Control' => 'no-store');
};

get '/' => sub {
    send_file('malicek.html');
};

get '/malicek' => sub {
    my %selfid = (
        app => $APP,
        version => $VERSION->stringify,
        agent => $AGENT,
    );
    if (session('cookies')) {
        return {
            %selfid,
            authenticated => \1,
        };
    } else {
        status(401);
        return {
            %selfid,
            authenticated => \0,
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
        session cookies => (tmpnam)[1];
        session ua => $ua;
        save_cookies;
        redirect('/malicek');
    } else {
        unauthenticated;
    }
};

get '/logout' => sub {
    session('ua')->get(
        "$alik/odhlasit",
    );
    logout;
    redirect('/malicek');
};

get '/status' => sub {
    return get_status;
};

get '/rooms' => sub {
    redirect('/rooms/');
};

get '/rooms/' => sub {
    my $r = session('ua')->get(
        "${alik}/k",
    );
    reconcile($r->decoded_content);
    return parse_rooms(sanitize($r->decoded_content));
};

post '/rooms/' => sub {
    my $room = body_parameters->get('name');
    my $r = session('ua')->post(
        "${alik}/k/pridat",
        {
            nazev => $room,
            odeslat => 'odeslat',
        },
    );
    if ($r->code == 302) {
        $r->header('Location') =~ /\/k\/(?<id>.+)$/;
        redirect('/rooms/' . $+{id});
    } else {
        status(409);
        return {};
    }
};

get '/rooms/:id' => sub {
    my ($r, $f);
    if (query_parameters->get('query')) {
        if (query_parameters->get('query') eq 'settings') {
            $f = \&parse_settings;
            $r = session('ua')->get(
                "${alik}/k/" . route_parameters->get('id') . '/nastaveni',
            );
            # FIXME: We also get a redirect if we ARE authenticated but
            # not in the requested room.
            unauthenticated
                if $r->is_redirect;
        } else {
            badrequest;
        }
    } else {
        $f = \&parse_chat;
        $r = session('ua')->get(
            "${alik}/k/" . route_parameters->get('id'),
        );
        reconcile($r->decoded_content);
    }
    if ($r->is_redirect) {
        if ($r->header('Location') =~ /err=(?<err>\d+)/) {
            status(403);
            halt({
                status => 403,
                reason => 'Forbidden',
                alik => int($+{err}),
            });
        } elsif ($r->header('Location') eq '/k/') {
            # We're already there but don't have the chat cookie
            # Leave and rejoin
            session('ua')->get(
                "${alik}/k/" . route_parameters->get('id') . '/odejit',
                Referer => "${alik}/k/" . route_parameters->get('id'),
            );
            $r = session('ua')->get(
                "${alik}/k/" . route_parameters->get('id'),
            );
        }
    }
    return &{$f}(sanitize($r->decoded_content));
};

post '/rooms/:id' => sub {
    my $action = body_parameters->get('action');
    if ($action eq 'leave') {
        session('ua')->get(
            "${alik}/k/" . route_parameters->get('id') . '/odejit',
            Referer => "${alik}/k/" . route_parameters->get('id'),
        );
        redirect('/rooms/');
    } elsif ($action eq 'post') {
        session('ua')->post(
            "${alik}/k/" . route_parameters->get('id'),
            {
                text => body_parameters->get('message'),
                prijemce => body_parameters->get('to') // 0,
                barva => body_parameters->get('color'),
            },
        );
    } elsif ($action eq 'report') {
        session('ua')->post(
            "${alik}/k/" . route_parameters->get('id') . '/neplecha',
            {
                vzkaz => body_parameters->get('report'),
            },
        );
    } elsif ($action eq 'op') {
        session('ua')->post(
            "${alik}/k/" . route_parameters->get('id') . '/spravce',
            {
                master => body_parameters->get('target'),
            },
        );
    } elsif ($action eq 'deop') {
        return session('ua')->post(
            "${alik}/k/" . route_parameters->get('id') . '/spravce',
            {
                demaster => 'ok',
            },
        )->code;
    } elsif ($action eq 'lock') {
        if (body_parameters->get('allowed') eq 'all') {
            session('ua')->post(
                "${alik}/k/" . route_parameters->get('id') . '/spravce',
                {
                    open => 'on',
                }
            );
        } else {
            my $lock;
            if (body_parameters->get('allowed') eq 'none') {
                $lock = [ 'kluky', 'holky' ];
            } elsif (body_parameters->get('allowed') eq 'boys') {
                $lock = 'kluky';
            } elsif (body_parameters->get('allowed') eq 'girls') {
                $lock = 'holky';
            } elsif (body_parameters->get('allowed') eq 'friends') {
                $lock = 'nekamarady';
            } else {
                badrequest;
            }
            session('ua')->post(
                "${alik}/k/" . route_parameters->get('id') . '/spravce',
                {
                    open => 'on',
                },
            );
            session('ua')->post(
                "${alik}/k/" . route_parameters->get('id') . '/spravce',
                {
                    lock => $lock,
                },
            );
        }
    } elsif ($action eq 'clear') {
        session('ua')->post(
            "${alik}/k/" . route_parameters->get('id') . '/spravce',
            {
                clear => 1,
            },
        );
    } elsif ($action eq 'kick') {
        session('ua')->post(
            "${alik}/k/" . route_parameters->get('id') . '/spravce',
            {
                kick => body_parameters->get('target'),
                doba => body_parameters->get('duration'),
                duvod => body_parameters->get('reason'),
            },
        );
    } elsif ($action eq 'ban') {
        session('ua')->post(
            "${alik}/k/" . route_parameters->get('id') . '/spravce',
            {
                kick => body_parameters->get('target'),
                doba => body_parameters->get('duration'),
                duvod => body_parameters->get('reason'),
                klubkick => 1,
            },
        );
    } elsif ($action eq 'destroy') {
        session('ua')->post(
            "${alik}/k/" . route_parameters->get('id') . '/master',
            {
                change => 1,
            },
        );
        redirect('/rooms/');
    } else {
        badrequest;
    }
    redirect('/rooms/' . route_parameters->get('id'));
};

get '/users' => sub {
    redirect('/users/');
};

get '/users/' => sub {
    return [];
};

# name, id, link, age, sex, avatar, admin, online
#    'realname';
#    'home';
#    'hobbies' => [];
#    'rank';
#    'registered';
#    'seen';
#    'blocked' => 0;
#    'gone' => 0;
#    'quest';
#    'likes';
#    'dislikes';
#    'pictures' => [];
#    'style';
#    'counter';
#    'visitors' => [];

get '/users/:id' => sub {
    my $r = session('ua')->get(
        "${alik}/u/" . route_parameters->get('id'),
    );
    reconcile($r->decoded_content);
    my $content = $r->decoded_content;
    if ($content =~ /<h1\sclass="tit">Vizitka\snenalezena<\/h1>/s) {
        # Never existed or no longer active; could distinguish
        return 404;
    }
    my $profile = Malicek::Profile->new();
    if ($content =~ /<div\sclass="mimoblok">/s) {
        # Blocked, some info to parse
    } else {
        # Potentially temporary blocked; what does that look like?
        $profile->name(
            ($content =~ /<title>(.+)\s–\sVizitka\s–\sAlík.cz<\/title>/sx)[0]
        );
        $profile->id(
            ($content =~ /<div\sstyle="color:\stransparent;[^"]+">(\d+)<\/div>/sx)[0]
        );
        return $profile->dump;
    }
};

sub game_lednicka {
    my $r = $_[0] // undef;
    unless ($r) {
        $r = session('ua')->get(
            "${alik}/-/lednicka",
        );
    }
    my $page = sanitize($r->decoded_content);
    if ($page =~ /Nejsi\spřihlášen/sx) {
        unauthenticated;
    }
    my $fridge = Malicek::Game::Lednicka->new(
        active =>
            $page !~/Je\spřičteno!/sx
            || 0,
        total =>
            ($page =~ /<a\shref="\/-\/lednicka".+?>\s([0-9\s]+)</sx)[0]
            =~ s/\s//sgr,
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
        $addition->amount($addition->amount =~ s/\+|\s//sgr);
        $addition->amount($addition->amount =~ s/&minus;/-/r);
        push $fridge->additions->@*, $addition;
    }
    return $fridge->dump;
}

get '/games/:game' => sub {
    if (route_parameters->get('game') eq 'lednicka') {
        return game_lednicka;
    }
    badrequest;
};

post '/games/:game' => sub {
    if (route_parameters->get('game') eq 'lednicka') {
        my $method;
        if (query_parameters->get('method')) {
            $method = query_parameters->get('method');
        } else {
            my $fridge = game_lednicka;
            unless ($fridge->{active}) {
                status(409);
                halt({
                    status => 409,
                    reason => 'Conflict',
                });
            }
            my $factor = 10 ** $fridge->{defrost} if $fridge->{defrost};
            my $defrost = $fridge->{defrost}
                ? ((int($fridge->{total} / $factor) + 1) * $factor) - $fridge->{total}
                : 0;
            my ($one, $c) = (0, 1.01);
            map { $c -= 0.01; $one += $c * $_->{amount} } @{$fridge->{additions}};
            $one = int($one / 100);
            my $status = get_status;
            my @time = localtime; $time[2] = 0 if $time[2] == 24;
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
    badrequest;
};

start;
