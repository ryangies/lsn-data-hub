package Algorithm::KeyGen;
use strict;
our $VERSION = 1.00;

use Perl::Module;
use Perl::Options qw(my_opts);

use base qw(Exporter);
our @EXPORT_OK = qw($KeyGen);
our %EXPORT_TAGS = (all=>[@EXPORT_OK]);

our $KeyGen = __PACKAGE__->new();

# ------------------------------------------------------------------------------
# new - Create a new key generator
# new
# new $key_length
# new $key_length, \@charset
# new $key_length, $charset
#
# parameters:
#
#   $key_length           Total length for the key.  This is the string length
#                         when C<-char_width> is 1 (normal behavior).  The
#                         default is 12.
#
#   \@charset             Characters (sequences) to use for the key.  The
#                         default is [0 .. 9].
#
#   $charset              Characters to use for the key in regex style, for 
#                         example the default would be '0-9'.  Can denote any
#                         characters where ord($char) < 126.
#
# options:
#
#   -char_width => $n     Width of each item in the character set.  Used if you 
#                         would like to use double-wide sequences such as 
#                         ['aa', 'bb', 'cc'].  The default is 1.
#
# N<1> Relationships between source digits and key length.
#
#   T = Total key length (C<$key_length>)
#   n = Number of random source digits
#
#      T = n + n/2
#     2T = 3n
#   2T/3 = n
#
# Possible values for T (C<$key_length>):
#
#   T =  3  6  9 12 15 18 21 24 27 30 33 36 39 42 45 48
#       -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
#   n =  2  4  6  8 10 12 14 16 18 20 22 24 26 28 30 32

# ------------------------------------------------------------------------------
#|test(!abort) # Create a new KeyGen
#|use Algorithm::KeyGen; 
#|Algorithm::KeyGen->new(9, 'MyCharset');
# ------------------------------------------------------------------------------

sub new {
  my $class = ref($_[0]) ? ref(shift) : shift;
  my $props = my_opts(\@_, {
    key_length => 12,
    charset => [0 .. 9],
    char_width => 1,
  });
  @_ and $props->{key_length} = shift;
  @_ and $props->{charset} = shift;
  my $charset = $props->{charset};
  # Convert older regexp style option (like 'a-z')
  if (!isa($charset, 'ARRAY') && !ref($charset)) {
    my $regexp = $charset;
    $props->{charset} = $charset = [];
    for (0 .. 126) {
      my $chr = chr($_);
      push @$charset, $chr if $chr =~ /[$regexp]/;
    }
  }
  $props->{charset_length} = scalar @$charset;
  bless $props, $class;
}

sub _chr {
  my $self = shift;
  my $idx = shift;
  throw Error::Programatic("Invalid character index")
    if ($idx < 0 || $idx >= $self->{charset_length});
  $self->{charset}[$idx];
}

sub _ord {
  my $self = shift;
  my $chr = shift;
  my $idx = grep_first_index {$_ eq $chr} @{$self->{charset}};
  $idx;
}

sub rand {
  my $self = shift;
  $self->_chr(int(CORE::rand($self->{charset_length})));
}

sub create {
  my $self = shift;
  my $o = '';
  my @n = ();
  my $count = ((2 * $self->{key_length}) / 3);
  throwf Error::Programatic("Invalid key_length: %s\n", $self->{key_length})
    unless $count == int($count);
  while (@n < $count) {
    push @n, $self->rand();
  }
  splice @n, $count;
  my ($a, $b, $c) = (0, 0, 0);
  while (@n) {
    ($a, $b) = (shift @n, shift @n);
    $c = $self->hash($a, $b);
    $o .= sprintf '%s%s%s', $a, $c, $b;
  }
  $o;
}

sub validate {
  my $self = shift;
  my $cw = $$self{char_width};
  my @n = $_[0] =~ /(.{$cw})/g;
  return unless @n == $self->{key_length};
  my ($a, $b, $c, $d) = (0, 0, 0, 0);
  while (@n) {
    ($a, $c, $b) = (shift @n, shift @n, shift @n);
    $d = $self->hash($a, $b);
    return unless $d eq $c;
  }
  $_[0];
}

sub hash {
  my $self = shift;
  my $left = shift;
  my $right = shift;
  my $a = $self->_ord($left);
  my $b = $self->_ord($right);
  my $s = $a + $b;
  my $l = $self->{charset_length};
  my ($q, $r) = int_div($s, $l);
  my $i = $q > 1 ? ($s/2) + $r : $r;
# warn "$a\t${s}/$l=${q}r$r=$i\t$b\n";
  $self->_chr($i);
}

1;

__END__

=test(!abort)

  use Algorithm::KeyGen qw($KeyGen);
  for (1 .. 100) {
    die unless $KeyGen->validate($KeyGen->create());
  }

=cut
