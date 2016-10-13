package AnyEvent::Stomper::Pool;

use 5.008000;
use strict;
use warnings;
use base qw( Exporter );

our $VERSION = '0.01_01';

use AnyEvent::Stomper;
use Scalar::Util qw( weaken );
use Carp qw( croak );


sub new {
  my $class  = shift;
  my %params = @_;

  my $self = bless {}, $class;

  unless ( defined $params{nodes} ) {
    croak 'Nodes not specified';
  }
  unless ( ref( $params{nodes} ) eq 'ARRAY' ) {
    croak 'Nodes must be specified as array reference';
  }
  unless ( @{ $params{nodes} } ) {
    croak 'Specified empty list of nodes';
  }

  $self->{nodes}              = $params{nodes};
  $self->{on_node_connect}    = $params{on_node_connect};
  $self->{on_node_disconnect} = $params{on_node_disconnect};
  $self->{on_node_error}      = $params{on_node_error};

  my %node_params;
  foreach my $name ( qw( login passcode vhost heart_beat connection_timeout
      reconnect_interval handle_params lazy ) )
  {
    next unless defined $params{$name};
    $node_params{$name} = $params{$name};
  }
  $self->{_node_params} = \%node_params;

  $self->_reset_internals;
  $self->_init;

  return $self;
}

sub get {
  my $self = shift;
  my $host = shift;
  my $port = shift;

  return $self->{_nodes_idx}{"$host:$port"};
}

sub nodes {
  my $self = shift;
  return @{ $self->{_nodes_list} };
}

sub random {
  my $self = shift;

  my $rand_index = int( rand( $self->{_pool_size} ) );

  return $self->{_nodes_list}[$rand_index];
}

sub next {
  my $self = shift;

  unless ( $self->{_node_index} < $self->{_pool_size} ) {
    $self->{_node_index} = 0;
  }

  return $self->{_nodes_list}[ $self->{_node_index}++ ];
}

sub force_disconnect {
  my $self = shift;

  foreach my $node ( @{ $self->{_nodes_list} } ) {
    $node->force_disconnect;
  }
  $self->_reset_internals;

  return;
}

sub _init {
  my $self = shift;

  my $nodes_idx = $self->{_nodes_idx};

  foreach my $node_params ( @{ $self->{nodes} } ) {
    my $hostport = "$node_params->{host}:$node_params->{port}";

    unless ( defined $nodes_idx->{$hostport} ) {
      $nodes_idx->{$hostport}
          = $self->_new_node( $node_params->{host}, $node_params->{port} );
    }
  }

  $self->{_nodes_list} = [ values %{ $self->{_nodes_idx} } ];
  $self->{_pool_size}  = scalar @{ $self->{_nodes_list} };

  return;
}

sub _new_node {
  my $self = shift;
  my $host = shift;
  my $port = shift;

  return AnyEvent::Stomper->new(
    %{ $self->{_node_params} },
    host          => $host,
    port          => $port,
    on_connect    => $self->_create_on_node_connect( $host, $port ),
    on_disconnect => $self->_create_on_node_disconnect( $host, $port ),
    on_error      => $self->_create_on_node_error( $host, $port ),
  );
}

sub _create_on_node_connect {
  my $self = shift;
  my $host = shift;
  my $port = shift;

  weaken($self);

  return sub {
    if ( defined $self->{on_node_connect} ) {
      $self->{on_node_connect}->( $host, $port );
    }
  };
}

sub _create_on_node_disconnect {
  my $self = shift;
  my $host = shift;
  my $port = shift;

  weaken($self);

  return sub {
    if ( defined $self->{on_node_disconnect} ) {
      $self->{on_node_disconnect}->( $host, $port );
    }
  };
}

sub _create_on_node_error {
  my $self = shift;
  my $host = shift;
  my $port = shift;

  weaken($self);

  return sub {
    my $err = shift;

    if ( defined $self->{on_node_error} ) {
      $self->{on_node_error}->( $err, $host, $port );
    }
  };
}

sub _reset_internals {
  my $self = shift;

  $self->{_nodes_idx}  = {};
  $self->{_nodes_list} = [];
  $self->{_pool_size}  = undef;
  $self->{_node_index} = 0;

  return;
}

1;
__END__

=head1 NAME

AnyEvent::Stomper::Pool - Connection pool blah blah

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
