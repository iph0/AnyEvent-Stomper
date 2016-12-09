package AnyEvent::Stomper::JSON;

use 5.008000;
use strict;
use warnings;

our $VERSION = '0.09_01';

use Cpanel::JSON::XS;


sub new {
  my $class = shift;

  my $self = bless {}, $class;

  my $json = Cpanel::JSON::XS->new;
  $json->ascii(1);
  $json->allow_blessed(1);
  $json->convert_blessed(1);
  $json->allow_tags(1);
  $self->{_json} = $json;

  return $self;
}

sub encode {
  my $self = shift;
  return $self->{_json}->encode(@_);
}

sub decode {
  my $self = shift;
  return $self->{_json}->decode(@_);
}

1;
__END__

=head1 NAME

AnyEvent::Stomper::JSON - JSON serializer for AnyEvent::Stomper

=head1 DESCRIPTION

JSON serializer for AnyEvent::Stomper.

=head1 CONSTRUCTOR

=head2 new()

Creates object of JSON serializer.

=head1 METHODS

=head2 encode()

=head2 decode()

=head1 SEE ALSO

L<AnyEvent::Stomper>

=head1 AUTHOR

Eugene Ponizovsky, E<lt>ponizovsky@gmail.comE<gt>

Sponsored by SMS Online, E<lt>dev.opensource@sms-online.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2016, Eugene Ponizovsky, SMS Online. All rights reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
