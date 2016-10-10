package AnyEvent::Stomper::Frame;

use 5.008000;
use strict;
use warnings;

our $VERSION = '0.01_01';

use Encode qw( decode );


sub new {
  my $class    = shift;
  my $command  = shift;
  my $headers  = shift;
  my $body     = shift;

  my $self = bless {}, $class;

  $self->{command} = $command;
  $self->{headers} = $headers || {};
  $self->{body}    = $body || '';

  return $self;
}

sub command {
  my $self = shift;
  return $self->{command};
}

sub headers {
  my $self = shift;
  return $self->{headers};
}

sub body {
  my $self = shift;
  return $self->{body};
}

sub decoded_body {
  my $self = shift;

  my $headers = $self->{headers};

  if ( defined $headers->{'content-type'}
    && $headers->{'content-type'} =~ m/;\s*charset=([^\s;]+)/ )
  {
    return decode( $1, $self->{body} );
  }

  return $self->{body};
}

1;
__END__

=head1 NAME

AnyEvent::Stomper::Frame - Class of STOMP frame for AnyEvent::Stomper

=head1 DESCRIPTION

=head1 CONSTRUCTOR

=head1 METHODS

=head2 command( [ $command ] )

=head2 headers( [ $headers ] )

=head2 body( [ $body ] )

=head1 SEE ALSO

L<AnyEvent::Stomper>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2016, Eugene Ponizovsky, E<lt>ponizovsky@gmail.comE<gt>.
All rights reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
