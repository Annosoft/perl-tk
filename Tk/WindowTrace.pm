package Tk::WindowTrace;

use strict;
use warnings;

use Tk;
use Tk::Xlib;
use Window;

use Carp qw( longmess );
use Time::HiRes qw( gettimeofday tv_interval );
use Try::Tiny;
use IO::File;
use POSIX ();

sub new {
    my ($pkg, $mainwindow, $show_code) = @_;

    my $self = bless { mw => $mainwindow }, $pkg;
    return $self;
}

sub mw {
    my ($self) = @_;
    return $self->{mw};
}

sub print {
    my ($self, @txt) = @_;
    print { $self->fh } @txt
      or die "Failed to write: $!";
    return;
}

sub fh {
    my ($self) = @_;
    return $self->{_out_fh} || \*STDOUT;
}

sub compress_to {
    my ($self, $fn) = @_;
    die "File $fn: exists already" if -e $fn;
    my $pid = open my $fh, '|-';
    if (!defined $pid) {
        die "Fail to gzip to $fn: $!";
    } elsif ($pid) {
        # parent
        $self->{_out_pid} = $pid;
        $self->{_out_fh} = $fh;
        $fh->autoflush(1);
        return $self;
    } else {
        # child
        try {
            # want gzip to finish, even if the parent is zapped
            die "setsid failed" if POSIX::setsid == -1;
            close STDOUT; # our STDOUT won't just reOPEN
            open STDOUT, '>', $fn
              or die "write to $fn: $!";
            exec qw( nice gzip -9 )
              or die "exec failed: $!";
        } catch {
            warn "compress_to subprocess $_";
            close STDERR; # _exit does not flush
            close STDOUT;
        };
        POSIX::_exit(127); # avoid triggering DESTROY
    }
}

sub DESTROY {
    my ($self) = @_;
    if (my $fh = $self->fh) {
        $self->print("\n" x 4); # a YAML-safe EOF mark
        close $fh or warn "Closing $fh: $!";
        delete $self->{_out_fh};
    }
}


=head2 bind($code)

Do the binding, after make changes to the event bind list.

 # don't log KeyPress
 $code = sub { my $ev = shift; delete $ev->{KeyPress} };

=head2 bind(%replace_ev)

Do the binding, after make changes to the event bind list.

 # log only position of KeyPress
 %replace_ev = (KeyPress => 'XY', KeyRelease => undef);

Values in %ev start with L<Tk:Ev> characters, or C<.> for none; then
optional space and keywords.

Valid keywords are C<raw> and C<hex> to include the XEvent dump.
These may contain memory soup from events shorter than struct XEvent.

=cut

sub bind {
    my ($self, @tweak_ev) = @_;
    my $M = $self->mw;

    # from Tk::bind POD of 804.029
    my %ev =
      qw( Activate         .
          ButtonPress      bsXY
          ButtonRelease    bsXY
          Circulate        p
          CirculateRequest p
          Colormap         .
          Configure        ahowB
          ConfigureRequest dhwB
          Create           hwB
          Deactivate       .
          Destroy          .
          Enter            dfms
          Expose           chw
          FocusIn          dm
          FocusOut         dm
          Gravity          .
          KeyPress         ksAKNXY
          KeyRelease       ksAKNXY
          Leave            dfms
          Map              o
          MapRequest       .
          Motion           sXY
          MouseWheel       D
          Property         .
          Reparent         o
          ResizeRequest    hw
          Unmap            .
          Visibility       s
       );
    foreach my $type (keys %ev) {
        # remove value placeholder
        $ev{$type} = '' if $ev{$type} eq '.';

        # add ubiquitous fields; though some are not always present,
        # and this is my false laziness
        $ev{$type} .= '#itTEWRS@';
    }

    if (1 == @tweak_ev && ref($tweak_ev[0])) {
        my ($prune_ev) = @tweak_ev;
        $prune_ev->(\%ev) if $prune_ev;
    } else {
        my %replace_ev = @tweak_ev;
        @ev{ keys %replace_ev } = values %replace_ev;
    }

    delete $ev{CirculateRequest}; # dnw? "no event type or button # or keysym"

    while (my ($type, $evstr) = each %ev) {
        next unless defined $evstr;
        my ($evchr, @evkey) = split / /, $evstr;
        my @evchr = defined $evchr ? (split //, $evchr) : ();
        my %evkey = map {( $_ => 1 )} @evkey;
        try {
            $M->bind(all => "<$type>",
                     [ \&__make_report, $self, $type,
                       keywords => \%evkey,
                       map {($_ => Ev("$_"))} @evchr]);
        } catch {
            local $" = ",";
            warn "[w] Couldn't bind <$type> with Ev(@evchr): $_";
        };
    }

    return;
}


sub __make_report { # not a method
    my ($obj, $self, $bound, %info) = @_;

    my $kw = delete $info{keywords}; # hashref of (key => 1)

    my @t = gettimeofday();
    my @l = localtime($t[0]);
    $info{wall} = sprintf('%4d-%02d-%02d %02d:%02d:%02d.%06d',
                          1900+$l[5],1+$l[4],@l[3,2,1,0], $t[1]);

    my $objkey = '!obj'; # sorts first
    $info{$objkey} = $obj;
#    $info{parent} = $obj->parent;
    $info{bound} = $bound;
    $info{longmess} = longmess();

    foreach my $k (sort keys %info) {
        next unless ref($info{$k});
        if ($k ne $objkey && $info{$k} == $obj) {
            $info{$k} = $info{OBJ};
        } elsif (ref($info{$k}) eq 'HASH') {
            next;
        } elsif ($info{$k}->isa('Tk::Widget')) {
            my $w = $info{$k};
            my %widg =
              (str => "$w",
               PathName => $w->PathName,
               XId => (try { scalar $obj->id } catch { "ERR:$_" }));
            $widg{destroyed} = 'NOT EXISTS' unless Tk::Exists($w);

            if ($kw->{hex} || $kw->{raw}) {
                my $ev = $w->XEvent; # see pod/Tcl-perl.pod
                $widg{raw_XEvent} = $kw->{hex} ? __hexdump(8, $$ev) : $ev;
            }
            foreach my $prop (qw( title text )) {
                try {
                    my $v = $w->cget("-$prop");
                    if (defined $v && (my $len = length($v)) > 75) {
                        substr($v, 35, $len-65, '~~~'); # abbreviate
                    }
                    $widg{$prop} = $v if defined $v;
                };
            }
            try {
                my $frame = $w->frame;
                $widg{frame} = $frame if defined $frame && $frame ne $w->id;
            } if $w->isa('Tk::Toplevel');
            $info{$k} = \%widg;

        } elsif ($info{$k}->isa('Window')) {
            $info{$k} = 'Window '.$info{$k}->id;
            # sometimes is uninitialised junk / a misinterpreted binary?
        }
    }

    $self->deliver_report(\%info);
    return;
}


# Would like to get a list of outer parents, up to the root window, so
# we can put this one in context; but XQueryTree can easily BadWindow.
#
# Safer with
#   `xwininfo -tree -id 0xF00` =~ m{^  Parent window id: (0x[0-9a-f]) }
# but that will be slow.
sub _id_path {
    my ($widg) = @_;
    my $win = Window->new($widg->id);
    my ($root, $parent);
    my @kid = $widg->Display->XQueryTree($win, $root, $parent);

    return join ", ", $win->id, $parent->id;
}

sub __hexdump {
    my ($step, $data) = @_;
    my $out = '';
    for (my $i=0; $i<length($data); $i+=$step) {
        $out .=
          sprintf("%4x: %s\n", $i,
                  join ' ',
                  map { sprintf("%02x", ord($_)) }
                  split //, substr($data, $i, $step));
    }
    return $out;
}



sub reporter {
    my ($self, @new) = @_;
    ($self->{reporter}) = @new if @new;
    return $self->{reporter};
}

sub deliver_report {
    my ($self, $infohash) = @_;
    my $reporter = $self->reporter;
    return $reporter->($self, $infohash) if $reporter;
}

1;
