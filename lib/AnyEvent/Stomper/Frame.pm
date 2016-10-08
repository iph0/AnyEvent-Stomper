package AnyEvent::Stomper::Frame;

use 5.008000;
use strict;
use warnings;

our $VERSION = '0.01_01';

use Encode qw( decode );

use constant {
  EOL    => "\r\n",
  RE_EOL => qr/\r?\n/,
};

my %ESCAPE_MAP = (
  "\r" => "\\r",
  "\n" => "\\n",
  ':'  => "\\c",
  "\\" => "\\\\",
);
my %UNESCAPE_MAP = reverse %ESCAPE_MAP;


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

sub parse {
  my $class = shift;
  my $str   = shift;

  my ( $header_str, $body )      = split( m/(?:${\(RE_EOL)}){2}/, $str );
  my ( $command, @header_pairs ) = split( m/${\(RE_EOL)}/, $header_str );

  my %headers;
  foreach my $pair ( @header_pairs ) {
    my ( $name, $value ) = split( /:/, $pair, 2 );
    $name  = _unescape($name);
    $value = _unescape($value);
    $headers{$name} = $value;
  }

  if ( defined $body ) {
    $body =~ s/\0(?:${\(RE_EOL)})*$//;
  }

  return $class->new( $command, \%headers, $body );
}

sub as_string {
  my $self = shift;

  my $headers = $self->{headers};

  unless ( defined $headers->{'content-length'} ) {
    $headers->{'content-length'} = length( $self->{body} );
  }

  my $str = uc( $self->{command} ) . EOL;
  while ( my ( $name, $value ) = each %{$headers} ) {
    $name  = _escape($name);
    $value = _escape($value);
    $str .= $name . ':' . $value . EOL;
  }
  $str .= EOL . $self->{body} . "\0";

  return $str;
}

{
  no strict qw( refs );

  foreach my $name ( qw( command headers body ) ) {
    *{$name} = sub {
      my $self = shift;

      if (@_) {
        $self->{$name} = shift;
      }

      return $self->{$name};
    };
  }
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

1;
__END__

=head1 NAME

AnyEvent::Stomper::Frame - Class of STOMP frame for AnyEvent::Stomper

=head1 DESCRIPTION

=head1 CONSTRUCTOR

=head1 METHODS

=head2 parse( $string )

=head2 command( [ $command ] )

=head2 headers( [ $headers ] )

=head2 body( [ $body ] )

=head2 as_string()

=head1 SEE ALSO

L<AnyEvent::Stomper>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2016, Eugene Ponizovsky, E<lt>ponizovsky@gmail.comE<gt>.
All rights reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
