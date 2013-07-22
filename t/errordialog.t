#!/usr/bin/perl -w
# -*- perl -*-

#
# $Id: $
# Author: Slaven Rezic
#

use strict;

use Tk;

BEGIN {
    if (!eval q{
	use Test::More;
	1;
    }) {
	print "1..0 # skip: no Test::More module\n";
	exit;
    }
}

plan tests => 8;

use_ok 'Tk::ErrorDialog';

my $mw = tkinit;
$mw->geometry("+10+10");

my $errmsg = "Intentional error.";
$mw->afterIdle(sub { die "$errmsg 1\n" });

my $ed;
$mw->after(100, sub {
	       my $dialog = search_error_dialog($mw);
	       isa_ok($dialog, "Tk::Dialog", "dialog");
	       $ed = $dialog;
	       my $error_stacktrace_toplevel = search_error_stacktrace_toplevel($mw);
	       isa_ok($error_stacktrace_toplevel, 'Tk::ErrorDialog', 'Found stacktrace window');
	       is($error_stacktrace_toplevel->state, 'withdrawn', 'Stacktrace not visible');
	       $error_stacktrace_toplevel->geometry('+0+0'); # for WMs with interactive placement
	       $dialog->SelectButton('Stack trace');
	       second_error();
	   });

MainLoop;

sub second_error {
    $mw->afterIdle(sub { die "$errmsg 2\n" });
    $mw->after(100, sub {
		   my $dialog = search_error_dialog($mw);
		   is($ed, $dialog, "ErrorDialog reused");
		   $dialog->Exit;
                   $mw->after(100, \& collide_errors);
	       });
}

my $collide_count; # not init
sub collide_errors {
    $mw->afterIdle(sub {
                       $collide_count++;
                       die "$errmsg 3\n";
                   });
    my $clear_later;
    my $do_clear = sub {
        return unless $collide_count > 0;
        my $dialog = search_error_dialog($mw);
        my $txt = $dialog->cget('-text'); # -message ?

        # It's not clear what message should be shown.  This just
        # matches pTk 804.029
        is($txt, "Error:  $errmsg 3\n", 'first message persists?');

        $dialog->Subwidget('B_OK')->invoke;
        $clear_later->cancel; # stop the repeat timer
        $mw->after(100, \& collide_check, $dialog);
    };
    $clear_later = $mw->repeat(25, $do_clear);
}

sub collide_check {
    my ($dialog) = @_;
    ok(Tk::Exists($dialog), 'post-collision, dialog still exists');
    is($dialog->state, 'withdrawn', 'ErrorDialog not visible');
    $mw->destroy;
}


sub search_error_dialog {
    my $w = shift;
    my $dialog;
    $w->Walk(sub {
		 return if $dialog;
		 for my $opt (qw(text message)) {
		     my $val = eval { $_[0]->cget("-$opt") };
		     if (defined $val && $val =~ m{\Q$errmsg}) {
			 $dialog = $_[0]->toplevel;
		     }
		 }
	     });
    $dialog;
}

sub search_error_stacktrace_toplevel {
    my $w = shift;
    my $toplevel;
    $w->Walk(sub {
		 return if $toplevel;
		 if ($_[0]->isa('Tk::ErrorDialog')) {
		     $toplevel = $_[0];
		 }
	     });
    $toplevel;
}

__END__
