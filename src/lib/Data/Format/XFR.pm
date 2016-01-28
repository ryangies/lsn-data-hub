package Data::Format::XFR;
use strict;
our $VERSION = 0;

use Exporter qw(import);
use Perl::Module;
use Data::OrderedHash;
use Error::Logical;
use MIME::Base64;
use Encode qw(is_utf8);

# ------------------------------------------------------------------------------
# %New - Constructor methods for data types
# ------------------------------------------------------------------------------

our %New = (
  '%' => sub {Data::OrderedHash->new(@_)},
  '@' => sub {[@_]},
  '$' => sub {shift},
);

# ------------------------------------------------------------------------------
# %Encodings - Supported encodings
# ------------------------------------------------------------------------------

our %Encodings = (
  '', 'uri',
  'base64', 'base64',
  'none', 'none',
);

# ------------------------------------------------------------------------------
# new - Constructor
# ------------------------------------------------------------------------------

sub new {
  my $classname = ref($_[0]) ? ref(shift) : shift;
  my $encoding = shift;
  my $self = bless {}, $classname;
  $self->set_encoding($encoding);
  $self;
}

# ------------------------------------------------------------------------------
# set_encoding - Set the content encoding
# ------------------------------------------------------------------------------

sub set_encoding {
  my $self = shift;
  my $arg = shift || '';
  my $encoding = $Encodings{$arg};
  return $self->{encoding} = $encoding;
}

# ------------------------------------------------------------------------------
# get_encoding - Return the content encoding
# ------------------------------------------------------------------------------

sub get_encoding {
  my $self = shift;
  return $self->{encoding};
}

# ------------------------------------------------------------------------------
# unescape - Unescape and decode values
# ------------------------------------------------------------------------------

sub unescape {
  my $self = shift;
  if ($self->{encoding} eq 'base64') {
    $_[0] = decode_base64($_[0]);
  } elsif ($self->{encoding} eq 'uri') {
    $_[0] =~ tr/+/ /;
    $_[0] =~ s/%([a-fA-F0-9]{2})/pack("C",hex($1))/eg;
  }
  Encode::decode('UTF-8', $_[0]);
}

# ------------------------------------------------------------------------------
# escape - Escape and encode values
# Expects a perl string (which will be UTF-8 encoded)
# ------------------------------------------------------------------------------

sub escape {
  my $self = shift;
  return unless defined $_[0];
  my $octets = is_utf8($_[0]) ? Encode::encode('UTF-8', $_[0]) : $_[0];
  if ($self->{encoding} eq 'base64') {
    return encode_base64($octets, '');
  } elsif ($self->{encoding} eq 'uri') {
    $octets =~ s/([^A-Za-z0-9_])/sprintf("%%%02X", ord($1))/eg;
  }
  return $octets;
}

# ------------------------------------------------------------------------------
# parse - Parse a string in to Perl data structures
# parse $string, [options]
# options:
#   '%' => sub {...} # HASH constructor (return a hash ref)
#   '@' => sub {...} # ARRAY constructor (return an array ref)
#   '$' => sub {...} # SCALAR constructor (return a scalar, not a scalar ref)
# ------------------------------------------------------------------------------

sub parse {
  my $self = shift;
  my $str = shift;
  throw Error::Logical '$str must begin with "%{", "@{", or "${"'
    unless $str =~ /^([\%\$\@]){/;
  my %new = (%New, @_);
  if ($1 eq '$') {
    my $value = substr $str, 2, -3;
    $value = $self->unescape($value);
    return $value;
  }
  my $root = $new{$1}();
  my $pos = 2;
  my $node = $root;
  my $parent = $root;
  my @parents = ();
  while (1) {
    my $open_pos = index($str, '{', $pos);
    my $close_pos = index($str, '}', $pos);
    if ($close_pos < $open_pos && $close_pos >= $[) {
      $node = pop @parents || $root;
      $pos = $close_pos + 1;
      next;
    }
    last if $open_pos < $[;
    my $key = substr $str, $pos, ($open_pos - $pos);
    my $type = substr $key, -1, 1, '';
    $key = $self->unescape($key);
    $pos = $open_pos + 1;
    if ($type eq '%' || $type eq '@') {
      push @parents, $node;
      $parent = $node;
      $node = $new{$type}();
      if (isa($parent, 'HASH')) {
        $parent->{$key} = $node;
      } elsif (isa($parent, 'ARRAY')) {
        push @{$parent}, $node;
      }
    } elsif ($type eq '$') {
      $open_pos = index($str, '{', $pos);
      $open_pos >= $[ && $open_pos < $close_pos and $close_pos = $open_pos - 1;
      my $value = $new{$type}(substr($str, $pos, ($close_pos - $pos)));
      $value = $self->unescape($value);
      if (isa($node, 'HASH')) {
        $node->{$key} = $value;
      } elsif (isa($node, 'ARRAY')) {
        push @{$node}, $value;
      } else {
        $$parent .= $value;
      }
      $pos = $close_pos + 1;
    } else {
      throw Error::Logical 'invalid data type';
    }
  }
  return $root;
}

# ------------------------------------------------------------------------------
# format - Create a transfer string from Perl data structures
# format \%hash
# format \@array
# format \$scalar
# ------------------------------------------------------------------------------

sub format {
  my $self = shift;
  my $result;
  my $node = shift;
  if (isa($node, 'HASH')) {
    $result = '%{';
    foreach my $k (keys %$node) {
      my $v = $node->{$k};
      $k = $self->escape($k);
      $result .= $k . $self->format($v);
    }
    $result .= '}';
  } elsif (isa($node, 'ARRAY')) {
    $result = '@{';
    $result .= $self->format($_) for @$node;
    $result .= '}';
  } elsif (isa($node, 'SCALAR')) {
    my $value = $$node; # copy
    $value = $self->escape($value);
    $result = '${' . $value . '}';
  } else {
    my $value = defined ($node) ? $self->escape($node) : '';
    $result = '${' . $value . '}';
  }
  $result;
}

1;

__END__

=pod:summary Data Transfer Format (XFR)

=pod:synopsis

=test(!abort)

  use Data::Format::XFR;
  use Data::OrderedHash;

  my $h = Data::OrderedHash->new(
    a => ['alpha', 'beta', 'copper'],
    b => {
      one => 1,
    },
    c => 'charlie',
  );

  my $xfr = Data::Format::XFR->new('base64');

  my $known = '%{YQ==@{${YWxwaGE=}${YmV0YQ==}${Y29wcGVy}}Yg==%{b25l${MQ==}}Yw==${Y2hhcmxpZQ==}}';
  my $str = $xfr->format($h);
  die "format error:\nstr: $str\n!= : $known" unless $str eq $known;

  my $h2 = $xfr->parse($str);
  die 'parse error' unless $h2->{a}[1] eq $h->{a}[1];

=pod:description

Implemented for the need to preserve hash order.

A delimited string consisting of encoded values.  The syntax is designed for 
efficient parsing and construction.

Reserved characters:

  % @ $ { }
  ! # ^ & * ~ - + = | \ ? ; : , . < > ( ) [ ] ' ` "

=cut
