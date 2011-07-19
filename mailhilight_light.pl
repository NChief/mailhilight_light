#!/usr/bin/perl
##################################
# mailhilight_light.pl by NChief
# 
# This script wil send you a mail if hilighted or get a private MSG
# The light version doesn not include crap like autoaway and screenaway. And this code is improved.
#
# Script requires sendmail and perl modules Mail::Sendmail (`cpan Mail::Sendmail`)
#
## Settings:
# - /set mailhilight_hiligon YourNick
#		This sets what to trigger on. its a list of triggers sepreated with space
#		It wil on trigger if its surrounded by non word characters (A-z_)
# - /set mailhilight_to you@email.com
#		Set wich email to send your hilights to.
# - /set mailhilight_from from@email.com
#		Set the from-mail
# - /set mailhilight_subject New hilights/messages
#		Sets the subject the mail i sent with
# - /set mailhilight_verbose 1
#		0 = no info(unless error), 1 = print on send, 2 = print on send and message save, 3 = debug
# - /set mailhilight_mode 3
#		1 = only send MSG, 2 = only send public hilights, 3 = send MSG and public hilights
# - /set mailhilight_context ON
#		Show context (Messages before and after hilight)
# - /set mailhilight_context_length 5
#		How many lines before hilight to get.
# - /set mailhilight_timer 60
#		How many seconds to wait before sending mail.
#
## Changelog
# 0.1
#	* Inital release (stripped version from mailhilight.pl)
# 0.2
#	* added join/part/quit etc to after-context
#
## TODO
# - somehow avoid sending same line several times? care?
# - dunno
#
##################################

use strict;
use warnings;
use Irssi qw(settings_add_str settings_get_str print settings_add_int settings_get_int settings_get_bool settings_add_bool);
use Irssi::Irc;
use Irssi::TextUI;
use Mail::Sendmail;
use utf8;
use POSIX;
use vars qw($VERSION %IRSSI);
use Data::Dumper;

$VERSION = "0.2";
%IRSSI = (
        authours => 'NChief',
        contact => 'NChief @ EFNet',
        name => 'mailhilight_light',
        description => 'Send mail on hilight/msg and no autoshit'
);

settings_add_str('mailhilight_light', 'mailhilight_hilighton', 'yournick somthingelse');
settings_add_str('mailhilight_light', 'mailhilight_to', 'your@mailadrrr.com');
settings_add_str('mailhilight_light', 'mailhilight_from', 'from@mailarrr.com');
settings_add_str('mailhilight_light', 'mailhilight_subject', 'New hilights/messages');
settings_add_int('mailhilight_light', 'mailhilight_verbose', 1); #0 = no info(unless error), 1 = print on send, 2 = print on send and message save, 3 = debug
settings_add_int('mailhilight_light', 'mailhilight_mode', 3); # 1 = only send MSG, 2 = only send public hilights, 3 = send MSG and public hilights
settings_add_bool('mailhilight_light', 'mailhilight_context', 1); # Send context? (messages before and after hilight)
settings_add_int('mailhilight_light', 'mailhilight_context_length', 5); # Lines (of context) before hilight to get.
settings_add_int('mailhilight_light', 'mailhilight_timer', 60);


# vars
my(@hilights, $mailto, $mailfrom, $subject, $verbose, $mode, $context, $context_length, $timer);
my $messages = {};
my $timebuffer = undef;

sub public_message {
	my ($server, $msg, $nick, $host, $channel) = @_;
	return if (!$server->{usermode_away} or $mode == 1 or defined($messages->{$channel}));
	foreach (@hilights) {
		if ($msg =~ /(\W|^)$_(\W|$)/i) {
			save_message($msg, $nick, $channel, $server, undef);
			last;
		}
	}
}

sub private_message {
	my ($server, $msg, $nick, $host) = @_;
	save_message($msg, $nick, undef, $server, undef) if ($server->{usermode_away} and $mode != 2 and !defined($messages->{$nick}));
}

sub direct_print {
	my ($dest, $text, $stripped) = @_;
	if(defined($messages->{$dest->{target}})) {
		save_message(undef, undef, $dest->{target}, undef, $stripped) unless ($messages->{$dest->{target}}->{'first'});
		$messages->{$dest->{target}}->{'first'} = 0 if $messages->{$dest->{target}}->{'first'};
	}
}

sub save_message {
	my ($msg, $nick, $channel, $server, $direct) = @_;
	my $time = strftime(Irssi::settings_get_str('timestamp_format'), localtime);
	if (defined($direct)) { # A direct print
		push(@{$messages->{$channel}->{'messages'}}, $time." ".gtlt($direct));
		foreach (@hilights) {
			if ($direct =~ /(\W|^)$_(\W|$)/i) {
				if(defined($timebuffer)) {
					Irssi::timeout_remove($timebuffer);
					print "Timer reset" if ($verbose >= 3);
				}
				$timebuffer = Irssi::timeout_add_once($timer * 1000, 'send_messages', undef);
				print CRAP "Hilight saved" if ($verbose >=2);
				return;
			}
		}
		print CRAP "Message saved" if ($verbose >=2);
	} elsif (defined($channel)) { # A channel hilight
		my $channel_rec = $server->channel_find($channel);
		my $nick_rec = $channel_rec->nick_find($nick);
		if(defined($messages->{$channel})) {
			$messages->{$channel}->{'first'} = 0;
		} else {
			$messages->{$channel}->{'first'} = 1;
			context_add($channel, $server) if ($context);
		}
		my $prefix = $nick_rec->{prefixes} || " ";
		push(@{$messages->{$channel}->{'messages'}}, $time.' &lt;'.$prefix.$nick.'&gt; '.$msg);
		print CRAP "Hilight saved" if ($verbose >=2);
		
		
		if(defined($timebuffer)) {
			Irssi::timeout_remove($timebuffer);
			print "Timer reset" if ($verbose >= 3);
		}
		$timebuffer = Irssi::timeout_add_once($timer * 1000, 'send_messages', undef);
	} else { # A priv msg
		if(defined($messages->{$nick})) {
			$messages->{$nick}->{'first'} = 0;
		} else {
			$messages->{$nick}->{'first'} = 1;
		}
		push(@{$messages->{$nick}->{'messages'}}, $time.' &lt;'.$nick.'&gt; '.$msg);
		print CRAP "MSG saved" if ($verbose >=2);
		if(defined($timebuffer)) {
			Irssi::timeout_remove($timebuffer);
			print "Timer reset" if ($verbose >= 3);
		}
		$timebuffer = Irssi::timeout_add_once($timer * 1000, 'send_messages', undef);
	}
}

sub send_messages {
	my $mail = undef;
	foreach my $target (keys %{$messages}) {
		if ($target =~ /^#/) {
			$mail .= "Hilight in ".$target.":<br />";
			$mail .= $messages->{$target}->{'context'}."<br />" if (defined($messages->{$target}->{'context'}));
			foreach my $msg (@{$messages->{$target}->{'messages'}}) {
				$mail .= $msg."<br />";
			}
		} else {
			$mail .= "MSG form ".$target.":<br />";
			foreach my $msg (@{$messages->{$target}->{'messages'}}) {
				$mail .= $msg."<br />";
			}
		}
	}
	if (defined($mail)) {
		my %sendmail = ( To => $mailto, From => $mailfrom, 'Content-Type' => 'text/html; charset="UTF-8"', Subject => $subject, Message => $mail );
		sendmail(%sendmail) or die($Mail::Sendmail::error);
		print CRAP "Hilights sent to ".$mailto if ($verbose >= 1);
	}
	$messages = {};
	$timebuffer = undef;
}

sub context_add {
	my($target, $server) = @_;
	my $window = $server->window_find_item($target);
	my $view = $window->view;
	my $line = $view->{buffer}->{cur_line};
	#my $context_before = undef;
	for(my $i = 0; $i < $context_length; $i++) {
		last unless defined $line;
		unshift(@{$messages->{$target}->{'messages'}}, gtlt(Irssi::strip_codes($line->get_text(1))));
		$line = $line->prev;
		last unless defined $line;
	}
	print CRAP "Context added" if ($verbose >= 3);
}

sub gtlt {
	my $content = shift;
	$content =~ s/</\&lt\;/g;
	$content =~ s/>/\&gt\;/g;
	return $content;
}

sub setup_changed { # update vars when setup is changed.
	@hilights = split(/\s/, settings_get_str('mailhilight_hilighton'));
	$mailto = settings_get_str('mailhilight_to');
	$mailfrom = settings_get_str('mailhilight_from');
	$subject = settings_get_str('mailhilight_subject');
	$verbose = settings_get_int('mailhilight_verbose');
	$mode = settings_get_int('mailhilight_mode');
	$context = settings_get_bool('mailhilight_context');
	$context_length = settings_get_int('mailhilight_context_length');
	$timer = settings_get_int('mailhilight_timer');
}

#init
setup_changed(); # to fill vars

#signals
Irssi::signal_add("message public", "public_message");
Irssi::signal_add_last("message private", "private_message");
Irssi::signal_add('print text', 'direct_print');
Irssi::signal_add_last('setup changed', "setup_changed");
