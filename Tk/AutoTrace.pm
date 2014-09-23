package Tk::AutoTrace;
use strict;
use warnings;

use Tk;
use Tk::WindowTrace;
use YAML 'Dump';


sub new {
    my ($pkg) = @_;
    my $M = Tk::MainWindow->new(-title => $pkg);
    $M->withdraw;
    my $self = bless { M => $M }, $pkg;
    $self->laterz;
    # someone else will call MainLoop
    return $self;
}

sub laterz {
    my ($self) = @_;
    $self->{M}->after(150, [ $self, 'setup' ]);
    return;
}

sub setup {
    my ($self) = @_;
    my $M = $self->{M};

    my @M = grep { $M != $_ } Tk::MainWindow->Existing
      or return $self->laterz;

    # ---  otterlace-specific  ---
    my $user = getpwuid($<);
    my $dir = "/var/tmp/otter_$user/ZMap/tk-logs";
    -d $dir
      or mkdir $dir, 0750
        or die "mkdir $dir: $!";
    utime undef, undef, $dir
      or die "touch $dir: $!";
    my $fn = "$dir/otterlace.$$.yaml.gz";
    # --- files will be auto-cleaned ---

    $M->destroy;
    foreach my $mw (@M) {
        my $t = Tk::WindowTrace->new($mw);
        $t->compress_to($fn)->reporter(\&__reporter);
        $t->bind(KeyPress => undef, KeyRelease => undef, # do not log passwords
                 Expose => undef, Motion => undef, # dull and noisy
                 '<GetPropLog>' => '#TRSfd@XYiEWh hex', # custom!
                );
        $M->{_windowtrace} = $t; # shove the ref into the window object
        warn "$self made $t for $mw writing to $fn\n";
        $t->print("# Writing for $0\n");
    }

    return;
}

sub __reporter { # not a method
    my ($wtrace, $infohash) = @_;

    if ($infohash->{bound} eq '<GetPropLog>') {
        # a quirk of XPropertyEvent vs. XVirtualEvent, that we put the
        # atom in the rootwindow field
        $infohash->{atom} = delete $infohash->{R};
    }

    $wtrace->print( Dump({ delete $infohash->{wall} => $infohash }) );
}


my $one = __PACKAGE__->new;
1;
