#!/usr/bin/perl
use strict;
use warnings;
use v5.16;
use Encode;
use IO::Async::Loop;
use IO::Async::Timer::Periodic;
use JSON::XS;
use LWP::UserAgent;
use String::Tagged;
use Tickit::Async;
use Tickit::Widget::Entry;
use Tickit::Widget::Static;
use Tickit::Widget::Scroller;
use Tickit::Widget::Scroller::Item::RichText;
use Tickit::Widget::Scroller::Item::Text;
use Tickit::Widget::HBox;
use Tickit::Widget::VBox;

my $host = 'https://alik.contyk.org/api';
my $user = 'uživatel';
my $pass = 'heslo';
my $color = '#657B83';
my $timer = 3;

my @highlight = ();

my ($room, $last, %users);

my $ua = LWP::UserAgent->new(cookie_jar => {},
                             requests_redirectable => ['GET', 'POST']);

# WTF
$ua->post("${host}/login",
          Content => encode_json({
                  user => Encode::decode_utf8($user),
                  pass => Encode::decode_utf8($pass)})
)->code() == 200 or die "Login failed!\n";

my $tickit = Tickit::Async->new();
my $vbox = Tickit::Widget::VBox->new(spacing => 1);
my $hbox = Tickit::Widget::HBox->new(spacing => 5);
my $ehbox = Tickit::Widget::HBox->new(spacing => 1);
my $prompt = Tickit::Widget::Static->new(text => '>');
my $entry = Tickit::Widget::Entry->new();
my $buffer = Tickit::Widget::Scroller->new(gravity => 'bottom');
my $users = Tickit::Widget::Static->new(text => '(users)');

sub msgfmt {
    my $msg = shift;
    if (!ref($msg)) {
        return Tickit::Widget::Scroller::Item::Text->new($msg);
    }
    my $txt = $msg->{time} // '';
    $txt .= ' ';
    if ($msg->{type} eq 'system') {
        $txt .= '-!-';
    } else {
        $txt .= '<' . $msg->{nick} . '>';
        if (@{$msg->{private}}) {
            $txt .= ' -> ';
            $txt .= '<' . $msg->{private}->[0] . '>';
        }
    }
    $txt .= ' ';
    my $offset = length($txt);
    $txt .= $msg->{message};
    my %tags;
    for my $token (($user, @highlight)) {
        while ($msg->{message} =~ /\Q${token}\E/g) {
            $tags{$token} //= [];
            push @{$tags{$token}}, pos($msg->{message}) - length($token);
        }
    }
    if (%tags || ($msg->{private} && @{$msg->{private}} && $msg->{nick} ne $user)) {
        my $tagged = String::Tagged->new($txt);
        for my $keyword (keys %tags) {
            for my $pos (@{$tags{$keyword}}) {
                $tagged->apply_tag($offset + $pos, length($keyword), b => 1);
            }
        }
        if ($msg->{private} && @{$msg->{private}} && $msg->{nick} ne $user) {
            $tagged->apply_tag($offset - length($user) - 2, length($user), b => 1);
        }
        return Tickit::Widget::Scroller::Item::RichText->new($tagged);
    } else {
        return Tickit::Widget::Scroller::Item::Text->new($txt);
    }
}

sub refresh {
    if ($room) {
        my $r = $ua->get("${host}/rooms/${room}");
        my $content = decode_json($r->decoded_content());
        my $index = -1;
        for (@{$content->{messages}}) {
            no warnings 'uninitialized';
            last if $last eq ($_->{nick} // ''). "\n"
                             . ($_->{message} // '') . "\n"
                             . ($_->{private}
                                 ? join("\n", sort @{$_->{private}})
                                 : '');
            $index++;
        }
        for (my $i = $index; $i >= 0; $i--) {
            $buffer->push(msgfmt($content->{messages}->[$i]));
        }
        $last = ($content->{messages}->[0]->{nick} // '') . "\n"
                . ($content->{messages}->[0]->{message} // '') . "\n"
                . ($content->{messages}->[0]->{private}
                    ? join("\n", sort @{$content->{messages}->[0]->{private}})
                    : '');
        $users->set_text(join("\n",
            map {
                (@{$_->{admin}} ? '@' : '')
                . $_->{name} . ' '
                . ($_->{sex} eq 'unisex'
                    ? '?'
                    : ($_->{sex} eq 'boy'
                        ? 'M'
                        : 'F')) . '/'
                . ($_->{age} // '?')
            } sort { $a->{link} cmp $b->{link} } @{$content->{users}}
        ));
        %users = (
            map {
                $_->{name} => $_
            } @{$content->{users}}
        );
    }
    $tickit->timer(after => $timer, __SUB__);
}

sub submit {
    my ($self, $input) = @_;
    $self->set_text('');
    if (substr($input, 0, 1) eq '/') {
        $input =~ /^\/(?<cmd>[^\s]+)\s*(?<args>.*)$/;
        my $cmd = $+{cmd};
        my @args = split(/\s+/, $+{args});
        if ($cmd =~ /r(ooms)?/i) {
            my $r = $ua->get("${host}/rooms");
            my $rooms = decode_json($r->decoded_content());
            $buffer->push(msgfmt("-------- -!- List of rooms\n"));
            for my $item (@{$rooms}) {
                $buffer->push(msgfmt($item->{name}.' ('.$item->{id}.')'));
                if (@{$item->{users}}) {
                    $buffer->push(msgfmt(':: '.join(', ',
                            map { (@{$_->{admin}} ? '@' : '') . $_->{name} }
                            @{$item->{users}})));
                }
                $buffer->push(msgfmt(" "));
            }
            $buffer->push(msgfmt('-------- -!- End of list'));
        } elsif ($cmd =~ /n(ames)?/i) {
            if ($hbox->children == 2) {
                $hbox->remove($users);
            } else {
                $hbox->add($users);
            }
        } elsif ($cmd =~ /j(oin)?/i && @args && !$room) {
            $buffer->push(msgfmt('-------- -!- Joining room "'.$args[0].'"'));
            $room = $args[0];
            $prompt->set_text("${room}>");
        } elsif ($cmd =~ /l(eave)?/i) {
            $buffer->push(msgfmt('-------- -!- Leaving room "'.$room.'"'));
            $ua->post("${host}/rooms/${room}",
                      Content => encode_json({ action => 'leave' }));
            undef $last;
            undef $room;
            $prompt->set_text('>');
        } elsif ($cmd =~ /q(uit)?/i) {
            $ua->get("${host}/logout");
            $tickit->teardown_term();
            exit;
        } elsif ($cmd =~ /m(sg)?/) {
            my $recipient = shift @args;
            if ($recipient && @args && $users{$recipient}) {
                $ua->post("${host}/rooms/${room}", Content => encode_json({
                    action => 'post',
                    to => $users{$recipient}->{id},
                    color => $color,
                    message => join(' ', @args)
                }));
            }
        } elsif ($cmd =~ /w(hois)?/) {
            my $recipient = shift @args;
            if ($users{$recipient}) {
                $buffer->push(msgfmt("-------- -!- Who is ${recipient}?"));
                $buffer->push(msgfmt('ID: ' . ($users{$recipient}->{id} // '?')));
                $buffer->push(msgfmt('Sex: ' . ($users{$recipient}->{sex} // '?')));
                $buffer->push(msgfmt('Age: ' . ($users{$recipient}->{age} // '?')));
                $buffer->push(msgfmt('Admin: ' . join(', ', @{$users{$recipient}->{admin}})))
                    if @{$users{$recipient}->{admin}};
                $buffer->push(msgfmt('Profile: https://www.alik.cz/u/' . $users{$recipient}->{link}));
                $buffer->push(msgfmt('Mail: https://www.alik.cz/@/' . $users{$recipient}->{link}));
                $buffer->push(msgfmt('Last message: ' . $users{$recipient}->{last}));
                $buffer->push(msgfmt('Present since: ' . $users{$recipient}->{since}));
                $buffer->push(msgfmt('-------- -!- End'));
            }
        } elsif ($cmd =~ /e(val)?/) {
            eval(join(' ', @args));
        }
    } else {
        if ($room) {
            $ua->post("${host}/rooms/${room}", Content => encode_json({
                action => 'post',
                to => 0,
                color => $color,
                message => $input
            }));
        }
    }
}

sub complete {
    $buffer->push(Tickit::Widget::Scroller::Item::Text("complete() called"));
}

$entry->set_on_enter(\&submit);

$hbox->add($buffer, expand => 1);
$hbox->add($users);

$ehbox->add($prompt);
$ehbox->add($entry, expand => 1);

$vbox->add($hbox, expand => 1);
$vbox->add($ehbox);

# XXX: IO::Async::Function for non-blocking?
$tickit->timer(after => $timer, \&refresh);

$entry->bind_keys("<Tab>", \&complete);

$tickit->set_root_widget($vbox);
$tickit->run();
