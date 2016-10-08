package AnyEvent::Stomper::Error;

use 5.008000;
use strict;
use warnings;

our $VERSION = '0.01_01';

our %ERROR_CODES = (
  E_CANT_CONN                  => 1,
  E_CANT_LOGIN                 => 2,
  E_IO                         => 3,
  E_CONN_CLOSED_BY_REMOTE_HOST => 4,
  E_CONN_CLOSED_BY_CLIENT      => 5,
  E_OPRN_ERROR                 => 6,
  E_UNEXPECTED_DATA            => 7,
  E_READ_TIMEDOUT              => 8,
);


sub new {
  my $class    = shift;
  my $err_msg  = shift;
  my $err_code = shift;

  my $self = bless {}, $class;

  $self->{message} = $err_msg;
  $self->{code}    = $err_code;

  return $self;
}

sub message {
  my $self = shift;
  return $self->{message};
}

sub code {
  my $self = shift;
  return $self->{code};
}

1;
__END__

=head1 NAME

AnyEvent::Stomper::Error - Class of error for AnyEvent::Stomper

=head1 DESCRIPTION

Class of error for L<AnyEvent::Stomper>. Objects of this class can be passed
to callbacks.

=head1 CONSTRUCTOR

=head2 new( $err_msg, $err_code )

Creates error object.

=head1 METHODS

=head2 message()

Get error message.

=head2 code()

Get error code.

=head1 SEE ALSO

L<AnyEvent::Stomper>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2016, Eugene Ponizovsky, E<lt>ponizovsky@gmail.comE<gt>.
All rights reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
