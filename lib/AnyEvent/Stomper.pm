package AnyEvent::Stomper;

use 5.008000;
use strict;
use warnings;
use base qw( Exporter );

our $VERSION = '0.01_01';

use AnyEvent::Stomper::Frame;
use AnyEvent::Stomper::Error;

use AnyEvent;
use AnyEvent::Handle;
use Scalar::Util qw( looks_like_number weaken );
use List::Util qw( max );
use Carp qw( croak );

our %ERROR_CODES;

BEGIN {
  %ERROR_CODES = %AnyEvent::Stomper::Error::ERROR_CODES;
  our @EXPORT_OK   = keys %ERROR_CODES;
  our %EXPORT_TAGS = ( err_codes => \@EXPORT_OK );
}

use constant {
  # Default values
  D_HOST       => 'localhost',
  D_PORT       => 61613,
  D_HEART_BEAT => [ 0, 0 ],

  %ERROR_CODES,

  # Operation status
  S_NEED_DO     => 1,
  S_IN_PROGRESS => 2,
  S_DONE        => 3,

  EOL    => "\n",
  RE_EOL => qr/\r?\n/,
};

my %SUBUNSUB_CMDS = (
  SUBSCRIBE   => 1,
  UNSUBSCRIBE => 1,
);

my %ESCAPE_MAP = (
  "\r" => "\\r",
  "\n" => "\\n",
  ':'  => "\\c",
  "\\" => "\\\\",
);
my %UNESCAPE_MAP = reverse %ESCAPE_MAP;


sub new {
  my $class  = shift;
  my %params = @_;

  my $self = bless {}, $class;

  $self->{host} = $params{host} || D_HOST;
  $self->{port} = $params{port} || D_PORT;
  $self->{login}    = $params{login};
  $self->{passcode} = $params{passcode};
  $self->{vhost}    = $params{vhost};

  if ( defined $params{heart_beat} ) {
    unless ( ref( $params{heart_beat} ) eq 'ARRAY' ) {
      croak qq{"heart_beat" must be specified as array reference};
    }
    foreach my $val ( @{ $params{heart_beat} } ) {
      if ( $val =~ /\D/ ) {
        croak qq{"heart_beat" values must be an integer numbers};
      }
    }

    $self->{heart_beat} = $params{heart_beat};
  }
  else {
    $self->{heart_beat} = D_HEART_BEAT;
  }

  $self->{lazy}          = $params{lazy};
  $self->{handle_params} = $params{handle_params} || {};
  $self->{on_connect}    = $params{on_connect};
  $self->{on_disconnect} = $params{on_disconnect};

  $self->connection_timeout( $params{connection_timeout} );
  $self->reconnect_interval( $params{reconnect_interval} );
  $self->on_error( $params{on_error} );

  $self->_reset_internals;
  $self->{_input_queue}      = [];
  $self->{_temp_queue}       = [];
  $self->{_pending_receipts} = {};
  $self->{_subs}             = {};

  unless ( $self->{lazy} ) {
    $self->_connect;
  }

  return $self;
}

sub execute {
  my $self     = shift;
  my $cmd_name = shift;

  my $cmd = $self->_prepare( $cmd_name, [@_] );
  $self->_execute($cmd);

  return;
}

# Generate methods
{
  no strict qw( refs );

  foreach my $name ( qw( send subscribe unsubscribe ack nack begin commit
      abort disconnect ) )
  {
    *{$name} = sub {
      my $self = shift;

      my $cmd = $self->_prepare( $name, [@_] );
      $self->_execute($cmd);

      return;
    }
  }
}

sub on_error {
  my $self = shift;

  if (@_) {
    my $on_error = shift;

    if ( defined $on_error ) {
      $self->{on_error} = $on_error;
    }
    else {
      $self->{on_error} = sub {
        my $err = shift;
        warn $err->message . "\n";
      };
    }
  }

  return $self->{on_error};
}

# Generate accessors
{
  no strict qw( refs );

  foreach my $name ( qw( host port ) ) {
    *{$name} = sub {
      my $self = shift;
      return $self->{$name};
    }
  }

  foreach my $name ( qw( connection_timeout reconnect_interval ) ) {
    *{$name} = sub {
      my $self = shift;

      if (@_) {
        my $seconds = shift;

        if ( defined $seconds
          && ( !looks_like_number($seconds) || $seconds < 0 ) )
        {
          croak qq{"$name" must be a positive number};
        }
        $self->{$name} = $seconds;
      }

      return $self->{$name};
    };
  }

  foreach my $name ( qw( on_connect on_disconnect ) ) {
    *{$name} = sub {
      my $self = shift;

      if (@_) {
        $self->{$name} = shift;
      }

      return $self->{$name};
    };
  }
}

sub _connect {
  my $self = shift;

  $self->{_handle} = AnyEvent::Handle->new(
    %{ $self->{handle_params} },
    connect          => [ $self->{host}, $self->{port} ],
    on_prepare       => $self->_create_on_prepare,
    on_connect       => $self->_create_on_connect,
    on_connect_error => $self->_create_on_connect_error,
    on_wtimeout      => $self->_create_on_wtimeout,
    on_rtimeout      => $self->_create_on_rtimeout,
    on_eof           => $self->_create_on_eof,
    on_error         => $self->_create_on_handle_error,
    on_read          => $self->_create_on_read,
  );

  return;
}

sub _create_on_prepare {
  my $self = shift;

  weaken($self);

  return sub {
    if ( defined $self->{connection_timeout} ) {
      return $self->{connection_timeout};
    }

    return;
  };
}

sub _create_on_connect {
  my $self = shift;

  weaken($self);

  return sub {
    $self->{_connected} = 1;
    $self->_login;

    if ( defined $self->{on_connect} ) {
      $self->{on_connect}->();
    }
  };
}

sub _create_on_connect_error {
  my $self = shift;

  weaken($self);

  return sub {
    my $err_msg = pop;

    my $err = _new_error(
      "Can't connect to $self->{host}:$self->{port}: $err_msg",
      E_CANT_CONN
    );
    $self->_disconnect($err);
  };
}

sub _create_on_wtimeout {
  my $self = shift;

  weaken($self);

  return sub {
    $self->{_handle}->push_write(EOL);
  };
}

sub _create_on_rtimeout {
  my $self = shift;

  weaken($self);

  return sub {
    my $err = _new_error( 'Read timed out.', E_READ_TIMEDOUT );
    $self->_disconnect($err);
  };
}

sub _create_on_eof {
  my $self = shift;

  weaken($self);

  return sub {
    my $err = _new_error( 'Connection closed by remote host.',
        E_CONN_CLOSED_BY_REMOTE_HOST );
    $self->_disconnect($err);
  };
}

sub _create_on_handle_error {
  my $self = shift;

  weaken($self);

  return sub {
    my $err_msg = pop;

    my $err = _new_error( $err_msg, E_IO );
    $self->_disconnect($err);
  };
}

sub _create_on_read {
  my $self = shift;

  weaken($self);

  my $cmd_name;
  my $headers;

  return sub {
    my $handle = shift;

    my $frame;

    while (1) {
      return if $handle->destroyed;

      if ( defined $cmd_name ) {
        my $content_length = $headers->{'content-length'};

        if ( defined $content_length ) {
          return if length( $handle->{rbuf} ) < $content_length + 1;
        }
        else {
          $content_length = index( $handle->{rbuf}, "\0" );
          return if $content_length < 0
        }

        my $body = substr( $handle->{rbuf}, 0, $content_length, '' );
        $handle->{rbuf} =~ s/^\0(?:${\(RE_EOL)})*//;

        $frame = _new_frame( $cmd_name, $headers, $body );

        undef $cmd_name;
        undef $headers;
      }
      else {
        $handle->{rbuf} =~ s/^(?:${\(RE_EOL)})+//;

        return unless $handle->{rbuf} =~ s/^(.+?)(?:${\(RE_EOL)}){2}//s;

        ( $cmd_name, my @header_strings ) = split( m/${\(RE_EOL)}/, $1 );
        foreach my $header_str (@header_strings) {
          my ( $name, $value ) = split( /:/, $header_str, 2 );
          $headers->{ _unescape($name) } = _unescape($value);
        }

        next;
      }

      $self->_process_frame($frame);
    }
  };
}

sub _prepare {
  my $self     = shift;
  my $cmd_name = uc(shift);
  my $args     = shift;

  my $cbs;
  if ( ref( $args->[-1] ) eq 'HASH' ) {
    $cbs = pop @{$args};
  }
  else {
    $cbs = {};
    if ( ref( $args->[-1] ) eq 'CODE' ) {
      if ( $cmd_name eq 'SUBSCRIBE' ) {
        $cbs->{on_message} = pop @{$args};
      }
      else {
        $cbs->{on_receipt} = pop @{$args};
      }
    }
  }
  my %headers = @{$args};
  my $body    = delete $headers{body};

  my $cmd = {
    name    => $cmd_name,
    headers => \%headers,
    body    => $body,
    %{$cbs},
  };

  if ( defined $cmd->{on_receipt} ) {
    $cmd->{need_receipt} = 1;
  }
  else {
    weaken($self);

    $cmd->{on_receipt} = sub {
      my $receipt = shift;
      my $err     = shift;

      if ( defined $err ) {
        $self->{on_error}->( $err, $receipt );
        return;
      }
    }
  }

  return $cmd;
}

sub _execute {
  my $self = shift;
  my $cmd  = shift;

  if ( $cmd->{name} eq 'SUBSCRIBE'
    && !defined $cmd->{on_message} )
  {
    croak '"on_message" callback must be specified';
  }

  unless ( $self->{_ready} ) {
    if ( defined $self->{_handle} ) {
      if ( $self->{_connected} ) {
        if ( $self->{_login_state} == S_NEED_DO ) {
          $self->_login;
        }
      }
    }
    elsif ( $self->{lazy} ) {
      undef $self->{lazy};
      $self->_connect;
    }
    else {
      if ( defined $self->{reconnect_interval}
        && $self->{reconnect_interval} > 0 )
      {
        unless ( defined $self->{_reconnect_timer} ) {
          $self->{_reconnect_timer} = AE::timer(
            $self->{reconnect_interval}, 0,
            sub {
              undef $self->{_reconnect_timer};
              $self->_connect;
            }
          );
        }
      }
      else {
        $self->_connect;
      }
    }

    push( @{ $self->{_input_queue} }, $cmd );

    return;
  }

  $self->_push_write($cmd);

  return;
}

sub _push_write {
  my $self = shift;
  my $cmd  = shift;

  my $headers = $cmd->{headers};

  if ( exists $SUBUNSUB_CMDS{ $cmd->{name} }
    || defined $cmd->{need_receipt} )
  {
    unless ( defined $headers->{receipt} ) {
      $headers->{receipt} = $self->{_session_id} . '@@'
          . $self->{_receipt_seq}++;
    }
    $self->{_pending_receipts}{ $headers->{receipt} } = $cmd;
  }
  elsif ( $cmd->{name} eq 'CONNECT' ) {
    $self->{_pending_receipts}{CONNECTED} = $cmd;
  }

  unless ( defined $cmd->{body} ) {
    $cmd->{body} = '';
  }
  unless ( defined $headers->{'content-length'} ) {
    $headers->{'content-length'} = length( $cmd->{body} );
  }

  my $frame_str = uc( $cmd->{name} ) . EOL;
  while ( my ( $name, $value ) = each %{$headers} ) {
    $frame_str .= _escape($name) . ':' . _escape($value) . EOL;
  }
  $frame_str .= EOL . $cmd->{body} . "\0";

  $self->{_handle}->push_write($frame_str);

  return;
}

sub _login {
  my $self = shift;

  my ( $cx, $cy ) = @{ $self->{heart_beat} };

  if ( $cy > 0 ) {
    $self->_rtimeout($cy);
  }

  my %headers = (
    'accept-version' => '1.0,1.1,1.2',
    'heart-beat'     => join( ',', $cx, $cy ),
  );
  if ( defined $self->{login} ) {
    $headers{login} = $self->{login};
  }
  if ( defined $self->{passcode} ) {
    $headers{passcode} = $self->{passcode};
  }
  if ( defined $self->{vhost} ) {
    $headers{host} = $self->{vhost};
  }

  weaken($self);
  $self->{_login_state} = S_IN_PROGRESS;

  $self->_push_write(
    { name    => 'CONNECT',
      headers => \%headers,

      on_receipt => sub {
        my $receipt = shift;
        my $err     = shift;

        if ( defined $err ) {
          $self->{_login_state} = S_NEED_DO;
          $self->_abort($err);

          return;
        }

        $self->{_login_state} = S_DONE;

        my $headers = $receipt->headers;

        if ( defined $headers->{'heart-beat'} ) {
          my ( $sx, $sy ) = split( /,/, $headers->{'heart-beat'} );

          if ( $sx > 0 ) {
            $self->_rtimeout( max( $cy, $sx ) );
          }
          if ( $sy > 0 ) {
            $self->_wtimeout( max( $cx, $sy ) );
          }
        }

        $self->{_ready}      = 1;
        $self->{_session_id} = $headers->{session};

        $self->_process_input_queue;
      },
    }
  );

  return;
}

sub _rtimeout {
  my $self     = shift;
  my $rtimeout = shift;

  $self->{_handle}->rtimeout_reset;
  $self->{_handle}->rtimeout( ( $rtimeout / 1000 ) * 3 );

  return;
}

sub _wtimeout {
  my $self     = shift;
  my $wtimeout = shift;

  $self->{_handle}->wtimeout_reset;
  $self->{_handle}->wtimeout( $wtimeout / 1000 );

  return;
}

sub _process_input_queue {
  my $self = shift;

  $self->{_temp_queue}  = $self->{_input_queue};
  $self->{_input_queue} = [];

  while ( my $cmd = shift @{ $self->{_temp_queue} } ) {
    $self->_push_write($cmd);
  }

  return;
}

sub _process_frame {
  my $self  = shift;
  my $frame = shift;

  if ( $frame->command eq 'MESSAGE' ) {
    $self->_process_message($frame);
  }
  elsif ( $frame->command eq 'RECEIPT' ) {
    $self->_process_receipt($frame);
  }
  elsif ( $frame->command eq 'ERROR' ) {
    if ( defined $self->{_pending_receipts}{CONNECTED} ) {
      $frame->headers->{'receipt-id'} = 'CONNECTED';
    }
    $self->_process_error($frame);
  }
  else {    # CONNECTED
    $frame->headers->{'receipt-id'} = 'CONNECTED';
    $self->_process_receipt($frame);
  }

  return;
}

sub _process_message {
  my $self = shift;
  my $frame = shift;

  my $headers = $frame->headers;
  my $sub_id  = $headers->{subscription} || $headers->{destination};
  my $cmd     = $self->{_subs}{$sub_id};

  unless ( defined $cmd ) {
    my $err = _new_error(
      qq{Don't know how process MESSAGE frame. Unknown subscription "$sub_id"},
      E_UNEXPECTED_DATA
    );
    $self->_disconnect($err);

    return;
  }

  $cmd->{on_message}->($frame);

  return;
}

sub _process_receipt {
  my $self  = shift;
  my $frame = shift;

  my $receipt_id = $frame->headers->{'receipt-id'};
  my $cmd        = delete $self->{_pending_receipts}{$receipt_id};

  unless ( defined $cmd ) {
    my $err = _new_error(
      qq{Unknown RECEIPT frame received: receipt-id=$receipt_id},
      E_UNEXPECTED_DATA
    );
    $self->_disconnect($err);

    return;
  }

  if ( exists $SUBUNSUB_CMDS{ $cmd->{name} } ) {
    my $headers = $cmd->{headers};
    my $sub_id  = $headers->{id} || $headers->{destination};

    if ( $cmd->{name} eq 'SUBSCRIBE' ) {
      $self->{_subs}{$sub_id} = $cmd;
    }
    else {    # UNSUBSCRIBE
      delete $self->{_subs}{$sub_id};
    }
  }
  elsif ( $cmd->{name} eq 'DISCONNECT' ) {
    $self->_disconnect;
  }

  $cmd->{on_receipt}->($frame);

  return;
}

sub _process_error {
  my $self  = shift;
  my $frame = shift;

  my $headers = $frame->headers;
  my $err     = _new_error( $headers->{message}, E_OPRN_ERROR );

  my $cmd;
  if ( defined $headers->{'receipt-id'} ) {
    $cmd = delete $self->{_pending_receipts}{ $headers->{'receipt-id'} };
  }

  if ( defined $cmd ) {
    $cmd->{on_receipt}->( $frame, $err );
  }
  else {
    $self->_disconnect( $err, $frame );
  }

  return;
}

sub _disconnect {
  my $self  = shift;
  my $err   = shift;
  my $frame = shift;

  my $was_connected = $self->{_connected};

  if ( defined $self->{_handle} ) {
    $self->{_handle}->destroy;
  }
  $self->_reset_internals;
  $self->_abort( $err, $frame );

  if ( $was_connected && defined $self->{on_disconnect} ) {
    $self->{on_disconnect}->();
  }

  return;
}

sub _reset_internals {
  my $self = shift;

  $self->{_handle}          = undef;
  $self->{_connected}       = 0;
  $self->{_login_state}     = S_NEED_DO;
  $self->{_ready}           = 0;
  $self->{_session_id}      = undef;
  $self->{_reconnect_timer} = undef;
  $self->{_receipt_seq}     = 1;

  return;
}

sub _abort {
  my $self  = shift;
  my $err   = shift;
  my $frame = shift;

  my @queued_commands = $self->_queued_commands;
  my %subs            = %{ $self->{_subs} };

  $self->{_input_queue}      = [];
  $self->{_temp_queue}       = [];
  $self->{_pending_receipts} = {};
  $self->{_subs}             = {};

  if ( !defined $err && @queued_commands ) {
    $err = _new_error( 'Connection closed by client prematurely.',
        E_CONN_CLOSED_BY_CLIENT );
  }

  if ( defined $err ) {
    my $err_msg  = $err->message;
    my $err_code = $err->code;

    $self->{on_error}->( $err, $frame );

    if ( %subs && $err_code != E_CONN_CLOSED_BY_CLIENT ) {
      foreach my $sub_id ( keys %subs ) {
        my $err = _new_error(
          qq{Subscription "$sub_id" lost: $err_msg},
          $err_code
        );

        my $cmd = $subs{$sub_id};
        $cmd->{on_receipt}->( undef, $err );
      }
    }

    foreach my $cmd (@queued_commands) {
      my $err = _new_error( qq{Operation "$cmd->{name}" aborted: $err_msg},
          $err_code );
      $cmd->{on_receipt}->( undef, $err );
    }
  }

  return;
}

sub _queued_commands {
  my $self = shift;

  return (
    values %{ $self->{_pending_receipts} },
    @{ $self->{_temp_queue} },
    @{ $self->{_input_queue} },
  );
}

sub _escape {
  my $str = shift;

  $str =~ s/([\r\n:\\])/$ESCAPE_MAP{$1}/ge;

  return $str;
}

sub _unescape {
  my $str = shift;

  $str =~ s/(\\[rnc\\])/$UNESCAPE_MAP{$1}/ge;

  return $str;
}

sub _new_frame {
  return AnyEvent::Stomper::Frame->new(@_);
}

sub _new_error {
  return AnyEvent::Stomper::Error->new(@_);
}

sub DESTROY {
  my $self = shift;

  if ( defined $self->{_handle} ) {
    $self->{_handle}->destroy;
  }

  if ( defined $self->{_pending_receipts} ) {
    my @queued_commands = $self->_queued_commands;

    foreach my $cmd (@queued_commands) {
      warn qq{Operation "$cmd->{name}" aborted:}
          . " Client object destroyed prematurely.\n";
    }
  }

  return;
}

1;
__END__

=head1 NAME

AnyEvent::Stomper - Flexible non-blocking STOMP client

=head1 SYNOPSIS

  use AnyEvent::Stomper;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for AnyEvent::Stomper, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.


=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

Eugene Ponizovsky, E<lt>iph@E<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2016 by Eugene Ponizovsky

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.14.2 or,
at your option, any later version of Perl 5 you may have available.

=cut
