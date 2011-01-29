package Dancer::Plugin::FlashMessage;

# ABSTRACT: Dancer plugin to display temporary messages, so called "flash messages".

use strict;
use warnings;
use Carp;

use Dancer ':syntax';
use Dancer::Plugin;

our $AUTHORITY = 'DAMS';
our $VERSION   = '0.2';

my $conf = plugin_setting;
my $token_name       = $conf->{token_name}       || 'flash';
my $session_hash_key = $conf->{session_hash_key} || '_flash';
my $queue            = $conf->{queue}            || 'key_single';
my $arguments        = $conf->{arguments}        || 'join';
my $dequeue          = $conf->{dequeue}          || 'by_key';

$arguments =~ m{\A(?: single | join | auto | array )\z}mxs
   or croak "invalid arguments setting '$arguments'";
sub _get_parameters {
   if ($arguments eq 'single') { return shift }
   elsif ($arguments eq 'join') { return join $, || '', @_ }
   elsif ($arguments eq 'array') { return [ @_ ] }
   return @_ > 1 ? [ @_ ] : shift;
}

if ($queue eq 'single') {
   register flash => sub {
      my $value = _get_parameters(@_);
      session $session_hash_key, $value;
      return $value;
   };
}
elsif ($queue eq 'multiple') {
   register flash => sub {
      my $value = _get_parameters(@_);
      my $flash = session($session_hash_key);
      session($session_hash_key, $flash = []) unless $flash;
      push @$flash, $value;
      return $value;
   };
}
elsif ($queue eq 'key_single') {
   register flash => sub {
      my $key = shift;
      my $value = _get_parameters(@_);
      my $flash = session($session_hash_key);
      session($session_hash_key, $flash = {}) unless $flash;
      $flash->{$key} = $value;
      return $value;
   };
}
elsif ($queue eq 'key_multiple') {
   register flash => sub {
      my $key = shift;
      my $value = _get_parameters(@_);
      my $flash = session($session_hash_key);
      session($session_hash_key, $flash = {}) unless $flash;
      push @{$flash->{$key}}, $value;
      return $value;
   };
}
else {
   croak "invalid queueing style '$queue'";
}


if ($dequeue eq 'by_key' and $queue !~ m{\Akey_}mxs) {
   croak "dequeuing style 'by_key' only available with 'key_*' queueing styles";
}
my $template_sub = {
   never => sub {
      shift->{$token_name} = session $session_hash_key;
      return;
   },
   always => sub {
      shift->{$token_name} = session $session_hash_key;
      session $session_hash_key, undef;
      return;
   },
   when_used => sub {
      my $cache;
      shift->{$token_name} = sub {
         if (! $cache) {
            $cache = session $session_hash_key;
            session $session_hash_key, undef;
         }
         return $cache;
      };
      return;
   },
   by_key => sub {
      my $flash = session($session_hash_key) || {};
      shift->{$token_name} = {
         map {
            my $key = $_;
            my $cache;
            $key => sub {
               if (! $cache) {
                  $cache = delete $flash->{$key};
               }
               return $cache;
            };
         } keys %$flash,
      };
   },
}->{$dequeue} or croak "invalid dequeuing style '$dequeue'";
before_template $template_sub;

register flash_flush => sub {
   my $flash = session $session_hash_key;
   return unless defined $flash;
   if ((ref($flash) eq 'HASH') && @_) {
      my @values = map { delete $flash->{$_} } @_;
      return unless defined wantarray();
      return $values[0] unless wantarray();
      return @values;
   }
   else {
      session $session_hash_key, undef;
      return $flash;
   }
};

register_plugin;

1;

__END__

=pod

=head1 NAME

Dancer::Plugin::FlashMessage - A plugin to display "flash messages" : short temporary messages

=head1 SYNOPSYS

Example with Template Toolkit: in your index.tt view or in your layout :

  <% IF flash.error %>
    <div class=error> <% flash.error %> </div>
  <% END %>

In your css :

  .error { background: #CEE5F5; padding: 0.5em;
           border: 1px solid #AACBE2; }

In your Dancer App :

  package MyWebService;

  use Dancer;
  use Dancer::Plugin::FlashMessage;

  get '/hello' => sub {
      flash error => 'Error message';
      template 'index';
  };

=head1 DESCRIPTION

This plugin helps you display temporary messages, so called "flash messages".
It provides a C<flash()> method to define the message. The plugin then takes
care of attaching the content to the session, propagating it to the templating
system, and then removing it from the session.

However, it's up to you to have a place in your views or layout where the
message will be displayed. But that's not too hard (see L</SYNOPSYS> and the
examples in L</CONFIGURATION>).

Basically, the plugin gives you access to the 'flash'(es) set in your controller
when you are in your views. It can be used to display flash messages.

By default, the plugin works using a descent configuration. However, you can
change the behaviour of the plugin. See L</CONFIGURATION>

=head1 INTERFACE

=head2 flash

  # sets the flash message for the warning key
  flash warning => 'some warning message';

This method inserts a flash message in the cache. What it puts inside and in
what manner depends on the queueing method, see below L</Queueing Styles>. By
default, it accepts two or more parameters, one consisting in the I<key> and
the second one consisting in the C<message>; in this case, the message is
associated to the given key, substituing any previous message for that key.

The method always returns the provided message.

=head2 flash_flush

   # flushes the whole flash cache, returning it
   my $flash = flash_flush();

   # if queuing method is a "key_*", flushes selected keys
   my @values = flash_flush(qw( warning error ));



=head1 CONFIGURATION

With no configuration whatsoever, the plugin will work fine, thus contributing
to the I<keep it simple> motto of Dancer.

=head2 Configuration Default Values

These are the default values. See below for a description of the keys

  plugins:
    FlashMessage:
      token_name:       flash
      session_hash_key: _flash
      queue:            key_single
      arguments:        join
      dequeue:          by_key

=head2 Options

=over

=item token_name

The name of the template token that will contain the hash of flash messages.
B<Default> : C<flash>

=item session_hash_key

You probably don't need that, but this setting allows you to change the name of
the session key used to store the hash of flash messages. It may be useful in
the unlikely case where you have key name conflicts in your session. B<Default> :
C<_flash>

=item queue

Sets the queueing style to one of the following allowed values:

=over

=item -

single

=item -

multiple

=item -

key_single

=item -

key_multiple

=back

See L</Queueing Styles> below for the details. B<Default> : C<key_single>

=item arguments

Sets how multiple values in a call to C<flash> should be handled. The
allowed values for this options are the following:

=over

=item -

single

=item -

join

=item -

auto

=item -

array

=back

See L</Multiple Parameters> below for the details. B<Default> : C<join>

=item dequeue

Sets the dequeueing style to one of the following allowed values:

=over

=item -

never

=item -

always

=item -

when_used

=item -

by_key

=back

See L</Dequeueing Styles> below for the details. B<Default> : C<by_key>

=back

=head2 Queueing Styles

There are various stiles for setting flash messages, which are
explained in the following list. The assumption in the documentation is
that the C<token_name> configuration is equal to the default C<flash>,
otherwise you have to substitute C<flash> with what you actually set.

The queueing style can be set with the C<queue> configuration, with
the following allowed values:

=over

=item B<< single >>

   flash $message;

this is the simplest style, one single message can be hold at any time.
The following call:

   flash 'hey you!';
   # ... later on...
   flash 'foo! bar!';

will replace any previously set message. In the template,
you will be able to get the latest set value with the C<flash> token:

   flash => 'foo! bar!'

=item B<< multiple >>

   flash $message;
   flash $other_message;

multiple messages are queued in the same order as they are put. The
following call:

   flash 'hey you!';
   # ... later on...
   flash 'foo! bar!';

will add C<$message> to the queue, and what you get in the template is
a reference to an array containing all the messages:

   flash => [
      'hey you!',
      'foo! bar!',
   ]

=item B<< key_single >>

   flash key1 => $message;
   flash key2 => $other_message;

you can have messages of different I<types> by providing a key, but only
one for each type. For example, you can set a I<warning> and an I<error>:

   flash warning => 'beware!';
   # ... later on...
   flash error => 'you made an error...';
   # ... and then...
   flash warning => 'ouch!';

Any further call to C<flash> with an already used key substitutes the
previous message with the new one.

In this case, the C<flash> token in the template returns an hash with
the keys you set and the last message introduced for each key:

   flash => {
      error   => 'you made an error...',
      warning => 'ouch!',
   }

=item B<< key_multiple >>

   flash key1 => $message;
   flash key2 => $other_message;
   flash key1 => $yet_another_message; # note key1 again

you can have messages of different I<types> by providing a key, and all
of them are saved. In the following example:

   flash warning => 'beware!';
   # ... later on...
   flash error => 'you made an error...';
   # ... and then...
   flash warning => 'ouch!';

In this case, the C<flash> token in the template returns an hash of
arrays, each containing the full queue for the particular key:

   flash => {
      error   => [ 'you made an error...' ],
      warning => [
         'beware!',
         'ouch!'
      ],
   }

=back

The default queueing style is I<key_single>, consistently with the previous releases
of this module.

=head2 Multiple Parameters

The queueing style is not the entire story, anyway. If you provide more parameters after
the C<$message>, this and all the following parameters are put in an anonymous
array and this is set as the new C<$message>. Assuming the C<simple> queueing
style, the following call:

   flash qw( whatever you want );

actually gives you this in the template token:

   flash => [ 'whatever', 'you', 'want' ];

This is useful if you don't want to provide a I<message>, but only parameters to be
used in the template to build up a message, which can be handy if you plan to make
translations of your templates. Consider the case that you have a parameter in a
form that does not pass the validation, and you want to flash a message about it;
the simplest case is to use this:

   flash "you have an error in the email parameter: '$input' is not valid"

but this ties you to English. On the other hand, you could call:

   flash email => $input;

and then, in the template, put something like this:

   you have an error in the <% flash.0 %> parameter: '<% flash.1 %>' is not valid

which lets you handle translations easily, e.g.:

   errore nel parametro <% flash.0 %>: '<% flash.1 %>' non risulta valido

If you choose to use this, you might find the C<arguments> configuration handy.
Assuming the C<multiple> queueing style and the following calls in the code:

   # in the code
   flash 'whatever';
   flash hey => 'you!';

you can set C<arguments> in the following ways:

=over

=item B<< single >>

this always ignores parameters after the first one. In the template, you get:

   flash => [
      'whatever',
      'hey',       # 'you!' was ignored
   ]

=item B<< join >>

this merges the parameters using C<$,> before enqueueing the message. In the
example, you get this in the template:

   flash => [
      'whatever',
      'heyyou!',   # join with $,
   ]

=item B<< auto >>

this auto-selects the best option, i.e. it puts the single argument as-is if there
is only one, otherwise generates an anonymous array with all of them. In the
template:

   flash => [
      'whatever',
      [ 'hey', 'you!' ],
   ]

=item B<< array >>

this always set the array mode, i.e. you get an array also when there is only
one parameter. This is probably your best choice if you plan to use multiple
parameters, because you always get the same structure in the template:

   flash => [
      [ 'whatever' ],
      [ 'hey', 'you!' ],
   ]

=back

The default handling style is I<join>.

=head2 Dequeueing Styles

When you put a message in the queue, it is kept in the User's session until it
is eventually dequeued. You can control how the message is deleted from the
session with the C<dequeue> parameter, with the following possibilities:

=over

=item B<< never >>

items are never deleted automatically, but will be flushed by the code in some
other way;

=item B<< always >>

items are always deleted from the session within the same call. Technically
speaking, using the session in this case is a bit overkill, because the session
is only used as a mean to pass data from the code to the template;

=item B<< when_used >>

items are all deleted when any of them is used in some way from the template. The
underlying semantics here is that if you get the chance to show a flash message
in the template, you can show them all so they are removed from the session. If
for some reason you don't get this chance (e.g. because you are returning a
redirection, and the template rendering will happen in the next call) the messages
are kept in the session;

=item B<< by_key >>

this style only applies if the queueing style is either C<key_single> or C<key_multiple>.
It is an extension of the C<when_used> case, but only used keys are deleted and
the unused ones are kept in the session for usage at some later call.

=back

The default dequeuing style is C<by_key>, consistently with the previous implementation
of this module.


=head1 COPYRIGHT

This software is copyright (c) 2011 by Damien "dams" Krotkine <dams@cpan.org>.

=head1 LICENCE

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=head1 AUTHORS

This module has been written by Damien "dams" Krotkine <dams@cpan.org>.

=head1 SEE ALSO

L<Dancer>

=cut
