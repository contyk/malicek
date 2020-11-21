#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use v5.16;

our $APP = 'Malicek';
use version 0.77; our $VERSION = version->declare('v0.1.14');
our $agent = "${APP}/${VERSION}";

# Malíček, an alternative interface for alik.cz
# See public/LICENSE.txt for license and authors.
#
# TODO: Switch to Moo for OOP
# TODO: Cleanup

use Archive::Tar;
use Dancer2;
use File::stat;
use File::Temp qw/:POSIX/;
use HTML::Entities;
use HTTP::Cookies;
use LWP::UserAgent;

set serializer => 'JSON';
set session => 'Simple';
set session_dir => '/tmp';

my $alik = 'https://www.alik.cz';

{
    package Malicek::Base;
    # Base class with common methods
    sub new {
        return bless {}, $_[0];
    }
}

{
    package Malicek::Room;
    our @ISA = qw/Malicek::Base/;
    # Represents a room in the rooms view
    sub name {
        return $_[0]->{name} = $_[1] // $_[0]->{name};
    }

    sub id {
        return $_[0]->{id} = $_[1] // $_[0]->{id};
    }

    sub users {
        my ($self, @users) = @_;
        return $_[0]->{users} = scalar(@users) ? [ @users ] : $_[0]->{users};
    }

    sub allowed {
        return $_[0]->{allowed} = $_[1] // $_[0]->{allowed};
    }

    sub dump {
        return {
            name => $_[0]->name,
            id => $_[0]->id,
            allowed => $_[0]->allowed // 'all',
            users => $_[0]->users && @{ $_[0]->users } ? [map { $_->dump } @{ $_[0]->users }] : [],
        };
    }
}

{
    package Malicek::Room::User;
    our @ISA = qw/Malicek::Base/;
    # Represents a user in the rooms view
    sub id {
        return $_[0]->{id} = $_[1] // $_[0]->{id};
    }

    sub name {
        return $_[0]->{name} = $_[1] // $_[0]->{name};
    }

    sub sex {
        return $_[0]->{sex} = $_[1] // $_[0]->{sex};
    }

    sub admin {
        return $_[0]->{admin} = $_[1] // $_[0]->{admin};
    }

    sub dump {
        return {
            id => $_[0]->id,
            name => $_[0]->name,
            sex => $_[0]->sex,
            admin => ($_[0]->admin // []),
        };
    }
}

{
    package Malicek::Chat;
    our @ISA = qw/Malicek::Base/;
    # Represents the chat room
    sub creator {
    }

    sub users {
    }

    sub messages {
    }
}

{
    package Malicek::Chat::User;
    our @ISA = qw/Malicek::Room::User/;
    # Represents a user in the chat room
    sub id {
        return $_[0]->{id} = $_[1] // $_[0]->{id};
    }

    sub link {
        return $_[0]->{link} = $_[1] // $_[0]->{link};
    }

    sub age {
        return $_[0]->{age} = $_[1] // $_[0]->{age};
    }

    sub since {
        return $_[0]->{since} = $_[1] // $_[0]->{since};
    }

    sub last {
        return $_[0]->{last} = $_[1] // $_[0]->{last};
    }

    sub dump {
        return {
            id => $_[0]->id ? 0 + $_[0]->id : undef,
            link => $_[0]->link,
            name => $_[0]->name,
            admin => ($_[0]->admin // []),
            age => $_[0]->age ? 0 + $_[0]->age : undef,
            sex => $_[0]->sex,
            since => $_[0]->since,
            last => $_[0]->last,
        };
    }
}

{
    package Malicek::Chat::Message;
    our @ISA = qw/Malicek::Base/;
    # Represents a message in a chat room
    sub type {
        return $_[0]->{type} = $_[1] // $_[0]->{type};
    }

    sub event {
        return $_[0]->{event} = $_[1] // $_[0]->{event};
    }

    sub private {
        return $_[0]->{private} = $_[1] // $_[0]->{private};
    }

    sub nick {
        return $_[0]->{nick} = $_[1] // $_[0]->{nick};
    }

    sub message {
        return $_[0]->{message} = $_[1] // $_[0]->{message};
    }

    sub time {
        return $_[0]->{time} = $_[1] // $_[0]->{time};
    }

    sub avatar {
        return $_[0]->{avatar} = $_[1] // $_[0]->{avatar};
    }

    sub color {
        return $_[0]->{color} = $_[1] // $_[0]->{color};
    }

    sub dump {
        return {
            type => $_[0]->type,
            event => $_[0]->event,
            private => $_[0]->private // [],
            nick => $_[0]->nick,
            message => $_[0]->message,
            time => $_[0]->time,
            avatar => $_[0]->avatar,
            color => $_[0]->color,
        };
    }
}

sub login {
    my ($user, $pass) = @_;
    my $ua = LWP::UserAgent->new(cookie_jar => {},
                                 agent => $agent,
                                 keep_alive => 1);
    my $r = $ua->post("${alik}/prihlasit",
                      [ login => $user, heslo => $pass,
                        typ => 'login_alik', pamatovat => 'on' ]);
    if ($r->is_redirect()) {
        return $ua->cookie_jar();
    } else {
        return undef;
    }
}

sub logout {
    if (session('cookies')) {
        unlink session('cookies') if -f session('cookies');
        app->destroy_session;
    }
}

sub reconcile {
    if ($_[0] =~ /<h3>Přihlášení<\/h3>/) {
        logout();
        return 0;
    }
    return 1;
}

sub load_cookies {
    my $cj = session('cookies')
        ? HTTP::Cookies->new(file => session('cookies'), autosave => 0)
        : HTTP::Cookies->new();
    return $cj;
}

sub save_cookies {
    my $cj = shift;
    $cj->save(session('cookies'));
}

sub sanitize {
    return $_[0] =~ s/\s+/ /sgr;
}

sub parse_status {
    $_[0] =~ /^Alik\.pocty\(
              "(?<mail>\d+)",\s
              "(?<people>\d+)!?",\s
              "(?<cash>[0-9\s]+)"\);$/sx;
    return (
        mail => int($+{mail}),
        people => int($+{people}),
        cash => int($+{cash} =~ s/\s//gr),
    );
}

sub parse_rooms {
    my $data = $_[0];
    my @rooms = ();
    while ($data =~ /"klubovna-stul(\sklubovna-zamek\sklubovna-zamek-(?<lock>[a-z]+?))?"
                     .+?(href="\/k\/(?<id>[a-z0-9-]+?)"\sclass="sublink.*?)?
                     stul-nazev"><u>(?<name>.+?)<\/u>
                     .*?<\/[ai]>(\s?<small.+?<\/small>)?\s<\/div>\s
                     (<div\sclass="klubovna-lidi(\s[a-z-]+)?"\sdata-pocet="\d+">(?<people>.+?)<\/div>)?
                    /sgx) {
        my $room = Malicek::Room->new();
        $room->name($+{name});
        $room->id($+{id});
        if (defined($+{lock})) {
            $room->allowed('none') if $+{lock} eq 'zluty';
            $room->allowed('boys') if $+{lock} eq 'cerveny';
            $room->allowed('girls') if $+{lock} eq 'modry';
            $room->allowed('friends') if $+{lock} eq 'zeleny';
        }
        if ($+{people}) {
            my @people = split('<a href="/u/', $+{people}); shift @people;
            my @users;
            for my $person (@people) {
                $person =~ /^(?<id>[^"]+).+?
                            class="sublink(?<sex>\sklubovna-[a-z]+)?".+?
                            <u><span(?<admin>.+?)?>(?<user>.+?)<\/span><\/u>
                           /sgx;
                my $user = Malicek::Room::User->new();
                $user->id($+{id});
                $user->name($+{user});
                if ($+{sex}) {
                    if ($+{sex} eq ' klubovna-kluk') {
                        $user->sex('boy');
                    } else {
                        $user->sex('girl');
                    }
                } else {
                    $user->sex('unisex');
                }
                $user->admin(defined($+{admin}) ? [qw/admin/] : []);
                push @users, $user;
            }
            $room->users(sort { $a->id cmp $b->id } @users);
        }
        push @rooms, $room->dump();
    }
    return sort { fc($a->{name}) cmp fc($b->{name}) } @rooms;
}

sub parse_chat {
    my ($name, $topic, $creator, $allowed, %users, @messages);
    $_[0] =~ /<!--reload\("zamceno"\)-->(?<lock>.*)<!--\/reload-->.+?
              Stůl:\s(?<name>[^<]+)<small\sid="bleskopopisek">
              <!--reload\("bleskopopisek"\)-->(?<topic>.*)<!--\/reload-->
              <\/small><\/h2><p>
              Stůl\szaložil\/a:\s<a\shref="\/u\/.+?">(?<creator>.+?)<\/a>/sx;
    $name = $+{name};
    $topic = $+{topic};
    $creator = $+{creator};
    $allowed = 'all';
    if ($+{lock}) {
        if (index($+{lock}, 'lock.png') != -1) {
            $allowed = 'none';
        } elsif (index($+{lock}, 'lockh.png') != -1) {
            $allowed = 'boys';
        } elsif (index($+{lock}, 'lockk.png') != -1) {
            $allowed = 'girls';
        } elsif (index($+{lock}, 'locknf.png') != -1) {
            $allowed = 'friends';
        }
    }
    while ($_[0] =~ /<option\svalue="(?<id>\d+)">(?<nick>.+?)<\/option>/sgx) {
        next if $+{id} == 0;
        my $user = Malicek::Chat::User->new();
        $user->name($+{nick});
        $user->id($+{id});
        $users{$user->name} = $user;
    }
    while ($_[0] =~ /(<span\sclass="(?<admin>guru|master|super[nkr]{1,3}|chef)"><\/span>)?
                     <h4\sclass="(?<sex>boy|girl|unisex)">
                     (?<nick>.+?)<\/h4>
                     <div\s*class="user-status">
                     (<p>Je\s*mi:\s*<b>(?<age>\d+)\s*let<\/b><\/p>)?
                     .+?href="\/u\/(?<link>.+?)"\sclass="vizitka"
                     .+?od\s+(?<since>.+?)<\/b>.+?
                     Poslední\s*zpráva:\s*<b>(?<last>.+?)<\/b>
                    /sgx) {
        $users{$+{nick}} //= Malicek::Chat::User->new();
        $users{$+{nick}}->name($+{nick});
        $users{$+{nick}}->link($+{link});
        $users{$+{nick}}->sex($+{sex});
        $users{$+{nick}}->since($+{since});
        $users{$+{nick}}->last($+{last});
        $users{$+{nick}}->age($+{age});
        if ($+{admin}) {
            my ($admin, $nick, @admin) = ($+{admin}, $+{nick});
            if ($admin =~ /^chef$/) {
                push @admin, 'chat';
            } elsif ($admin =~ /^super/) {
                push @admin, 'rooms' if $admin =~ /^super.*k.*$/;
                push @admin, 'boards' if $admin =~ /^super.*n.*$/;
                push @admin, 'blog' if $admin =~ /^super.*r.*$/;
            } elsif ($admin =~ /^master|guru$/) {
                push @admin, $admin;
            } else {
                @admin = ();
            }
            $users{$nick}->admin([@admin]);
        }
    }
    while ($_[0] =~ /<p\sclass="(?<type>system|c-1)">
                     (<span\sclass="time">(?<time>\d{1,2}:\d{2}:\d{2})<\/span>)?
                     (<img\s.+?\/\/(?<avatar>.+?)">)?
                     \s*
                     (?<message>.+?)<\/p>
                    /sgx) {
        my $msg = Malicek::Chat::Message->new();
        $msg->type($+{type} eq 'system' ? 'system' : 'chat');
        $msg->event(undef);
        if ($+{time}) {
            $msg->time(length($+{time}) == 8 ? $+{time} : '0' . $+{time});
        }
        $msg->avatar($+{avatar} ? 'https://' . $+{avatar} : undef);
        if ($+{type} eq 'system') {
            $msg->message($+{message} =~ s/<.+?>|\s*$//sgxr);
            if ($msg->message() =~ /^Kamarád(ka)? (?<nick>.+) si přisedla? ke stolu\.$/) {
                $msg->event({type => 'join', source => $+{nick}, target => undef});
            } elsif ($msg->message() =~ /^Kamarád(ka)? (?<nick>.+) (vstala? od|přeš(el|la) k jinému) stolu\.$/) {
                $msg->event({type => 'part', source => $+{nick}, target => undef});
            } elsif ($msg->message() =~ /^Alík odebral kamarád(ovi|ce) (?<nick>.+) místo u stolu z důvodu neaktivity.$/) {
                $msg->event({type => 'part', source => $+{nick}, target => undef});
            } elsif ($msg->message() =~ /^Kamarád(ka)? (?<nick>.+) zamkla? stůl/) {
                $msg->event({type => 'lock', source => $+{nick}, target => undef});
            } elsif ($msg->message() =~ /^Kamarád(ka)? (?<nick>.+) odemkla? stůl/) {
                $msg->event({type => 'unlock', source => $+{nick}, target => undef});
            } elsif ($msg->message() =~ /^Kamarád(ka)? (?<nick>.+) vyčistila? stůl\.$/) {
                $msg->event({type => 'clear', source => $+{nick}, target => undef});
            } elsif ($msg->message() =~ /^Kamarád(ka)? (?<nick>.+) byla? vyhozena? správcem od stolu\.$/) {
                $msg->event({type => 'kick', source => undef, target => $+{nick}});
            } elsif ($msg->message() =~ /^Kamarád(ka)? (?<nick>.+) předala? správce\.$/) {
                $msg->event({type => 'oper', source => $+{nick}, target => undef});
            } else {
                $msg->event({type => 'unknown', source => undef, target => undef});
            }
        } else {
            $+{message} =~ /(?<private><span\sclass="septani"><\/span>)?
                            <font\scolor="((?<color>\#[a-fA-F0-9]{6})|.+?)">
                            <strong>(?<nick>.+?)<\/strong>
                            (\s⇨\s(<em>)?(?<to>.*?)(<\/em>)?)?
                            :\s(?<msg>.+?)<\/font>
                           /sgx;
            $msg->private($+{private} ? [($+{to} || undef)] : []);
            $msg->color($+{color});
            $msg->nick($+{nick});
            my $raw = $+{msg};
            $raw =~ s/<img\sclass="smiley"\ssrc=".+?"\salt="(.+?)">?/[$1]/sgx;
            $raw =~ s/<.+?>//sgx;
            $msg->message(decode_entities($raw));
            undef $msg if @{$msg->private} && ! $msg->private->[0];
        }
        push @messages, $msg if $msg;
    }
    return (
        name => $name,
        topic => $topic,
        creator => $creator,
        allowed => $allowed,
        users => [ map { $users{$_}->dump } keys %users ],
        messages => [ map { $_->dump } @messages ],
    );
}

sub parse_settings {
    $_[0] =~ /\sname="system"(?<system>\schecked)?
              .*?name="barvy"(?<colors>\schecked)?
              .*?name="cas"(?<time>\schecked)?
              .*?name="ikony"(?<avatars>\schecked)?
              .*?value="(?<refresh>\d+)"\sselected
              .*?name="highlight"(?<highlight>\schecked)?
              .*?name="barva"\svalue="(?<color>\#[a-fA-F0-9]{6})"
             /sgx;
    return (
        system => $+{system} ? \1 : \0,
        colors => $+{colors} ? \1 : \0,
        time => $+{time} ? \1 : \0,
        avatars => $+{avatars} ? \1 : \0,
        refresh => int($+{refresh}),
        highlight => $+{highlight} ? \1 : \0,
        color => $+{color},
    );
}

sub get_status {
    my $ua = LWP::UserAgent->new(cookie_jar => load_cookies(),
                                 agent => $agent);
    my $r = $ua->get("${alik}/-/online");
    redirect('/') unless $r->decoded_content();
    save_cookies($ua->cookie_jar());
    return {parse_status(sanitize($r->decoded_content()))};
}

get '/' => sub {
    my %selfid = (
        app => $APP,
        version => $VERSION->stringify(),
        agent => $agent,
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
    my ($user, $pass) = (body_parameters->get('user'), body_parameters->get('pass'));
    my $cj = login($user, $pass);
    if ($cj) {
        session cookies => (tmpnam())[1];
        save_cookies($cj);
    } else {
        logout();
    }
    redirect('/');
};

get '/logout' => sub {
    my $ua = LWP::UserAgent->new(cookie_jar => load_cookies(),
                                 agent => $agent);
    $ua->get("$alik/odhlasit");
    logout();
    redirect('/');
};

get '/status' => sub {
    redirect('/') unless session('cookies');
    return get_status();
};

get '/rooms' => sub {
    redirect('/') unless session('cookies');
    my $ua = LWP::UserAgent->new(cookie_jar => load_cookies(),
                                 agent => $agent);
    my $r = $ua->get("${alik}/k");
    redirect('/') unless reconcile($r->decoded_content());
    save_cookies($ua->cookie_jar());
    return [parse_rooms(sanitize($r->decoded_content()))];
};

# TODO: Figure out how to determine we were kicked out for
# inactivity without autorejoining the room.
get '/rooms/:id' => sub {
    redirect('/') unless session('cookies');
    my $ua = LWP::UserAgent->new(cookie_jar => load_cookies(),
                                 agent => $agent,
                                 max_redirect => 0);
    my ($r, $f);
    if (query_parameters->get('query')
        && query_parameters->get('query') eq 'settings') {
        $f = \&parse_settings;
        $r = $ua->get("${alik}/k/".route_parameters->get('id').'/nastaveni');
    } else {
        $f = \&parse_chat;
        $r = $ua->get("${alik}/k/".route_parameters->get('id'));
    }
    redirect('/') unless reconcile($r->decoded_content());
    save_cookies($ua->cookie_jar());
    if ($r->code == 302) {
        if ($r->header('Location') =~ /err=(?<err>\d+)/) {
            status(403);
            return {
                error => 0 + $+{err}
            };
        } elsif ($r->header('Location') eq '/k/') {
            $ua->get("${alik}/k/".route_parameters->get('id').'/odejit',
                     Referer => "${alik}/k/".route_parameters->get('id'));
            if (query_parameters->get('query')) {
                # How did we get here?
                status(501);
                return {
                    error => 501
                };
            } else {
                $r = $ua->get("${alik}/k/".route_parameters->get('id'));
                save_cookies($ua->cookie_jar());
            }
        }
    }
    return {&{$f}(sanitize($r->decoded_content()))};
};

post '/rooms/:id' => sub {
    redirect('/') unless session('cookies');
    my $action = body_parameters->get('action');
    my $ua = LWP::UserAgent->new(cookie_jar => load_cookies(),
                                 agent => $agent);
    if ($action eq 'leave') {
        $ua->get("${alik}/k/".route_parameters->get('id').'/odejit',
                 Referer => "${alik}/k/".route_parameters->get('id'));
        redirect('/rooms');
    } elsif ($action eq 'post') {
        $ua->post("${alik}/k/".route_parameters->get('id'),
                   { text => body_parameters->get('message'),
                     prijemce => body_parameters->get('to') // 0,
                     barva => body_parameters->get('color'),
                   });
        redirect('/rooms/'.route_parameters->get('id'));
    } else {
        redirect('/rooms/'.route_parameters->get('id'));
    }
};

get '/app' => sub {
    redirect '/app/';
};

get '/app/:file?' => sub {
    my $file = route_parameters->get('file') // 'malicek.html';
    if ($file eq 'malicek.tar.gz') {
        my @files = qw{
            malicek.pl
            public/malicek.html
            public/malicek.css
            public/malicek.js
            public/wtf.html
            public/LICENSE.txt
        };
        my $regenerate = 0;
        for (@files) {
            next if (-f "public/${file}"
                     && stat("public/${file}")->[9] >= stat($_)->[9]);
                 $regenerate = 1;
        }
        if ($regenerate) {
            my $tar = Archive::Tar->new();
            $tar->add_files(@files);
            $tar->write("public/${file}", COMPRESS_GZIP);
        }
    }
    send_file($file);
};

sub game_lednicka {
    my $r = $_[0] // undef;
    unless ($r) {
        my $ua = LWP::UserAgent->new(cookie_jar => load_cookies(),
                                     agent => $agent);
        $r = $ua->get("${alik}/-/lednicka");
        save_cookies($ua->cookie_jar());
    }
    my $page = sanitize($r->decoded_content());
    if ($page =~ /Nejsi\spřihlášen/sx) {
        logout();
        redirect('/');
    }
    my %fridge;
    $fridge{active} = $page !~ /Je\spřičteno!/sx || 0;
    $fridge{total} = ($page =~ /<a\shref="\/-\/lednicka".+?>\s*([0-9\s]+)</sx)[0];
    $fridge{total} =~ s/\s//g; $fridge{total} += 0;
    $fridge{defrost} = $fridge{active} ? ($page !~ /onclick="alert/sx || 0) : 0;
    $fridge{defrost} = ($page =~ /Odmrazení\sčtyřčíslí/sx ? 4 : 3) if $fridge{defrost};
    my @additions;
    while ($page =~ /<tr\stitle="(?<when>.+?)".+?>
                      <a\shref=".+?"\starget="_parent">(?<who>.+?)<\/a>\spřičetla?\s
                     (?<method>.+?)<.+?>
                     (?<amount>.+?)</sxg) {
        my ($when, $who, $method, $amount) = ($+{when}, $+{who}, $+{method}, $+{amount});
        $amount =~ s/\+|\s//g; $amount =~ s/&minus;/-/;
        push @additions, {
            who => $who,
            when => $when,
            method => $method,
            amount => 0 + $amount
        };
    }
    $fridge{additions} = [ @additions ];
    return { %fridge };
}

get '/games/:game' => sub {
    redirect('/') unless session('cookies');
    if (route_parameters->get('game') eq 'lednicka') {
        return game_lednicka();
    }
    status(400);
    return {};
};

post '/games/:game' => sub {
    redirect('/') unless session('cookies');
    if (route_parameters->get('game') eq 'lednicka') {
        my $ua = LWP::UserAgent->new(cookie_jar => load_cookies(),
                                     agent => request->user_agent());
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
            my $defrost = $fridge->{defrost} ? ((int($fridge->{total} / $factor) + 1) * $factor) - $fridge->{total} : 0;
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
        return game_lednicka($ua->post("${alik}/-/lednicka", [ pricti => $method ]));
    }
    status(400);
    return {};
};

start;
