package Window;
use strict;
use warnings;

=head1 NAME

Window - an X11 window id

=head1 SYNOPSIS

 use Window;
 use Tk::Xlib;
 my $win = Window->new( $widget->id );
 
 my ($root, $parent);
 my @kid = $widget->Display->XQueryTree($win, $root, $parent);
 # Beware, risk of fatal BadWindow error!
 # @kid, $root and $parent are new Window objects

=head1 DESCRIPTION

This class represents an X11 window id.

=cut


# there was no constructor, they come from Tk/Xlib.so
sub new {
    my ($pkg, $id) = @_;
    $id = hex($id) if $id =~ /^0x/;
    my $obj = \$id;
    bless $obj, $pkg;
    return $obj;
}

sub id {
    my ($self) = @_;
    return sprintf('0x%x', $$self);
}

1;
