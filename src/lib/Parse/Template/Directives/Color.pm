package Parse::Template::Directives::Color;
use strict;
our $VERSION = 0;

use Perl::Module;
use Error::Logical;
use Data::Hub::Util qw(:all);

our %Directives;

# `#69a` is a shortcut for `#6699aa`
our $RE_RGB_HEX3 = qr/^#([a-f0-9])([a-f0-9])([a-f0-9])$/i;

# `#102030`
our $RE_RGB_HEX6 = qr/^#([a-f0-9]{2})([a-f0-9]{2})([a-f0-9]{2})$/i;

# `rgba(128,128,128,1)
our $RE_RGBA = qr/^rgba\((\d{1,3}),(\d{1,3}),(\d{1,3}),([\d\.]{1,3})\)$/i;

# `rgba(10%,10%,10%,1)
# No support

# `rgb(128,128,128)
our $RE_RGB = qr/^rgb\((\d{1,3}),(\d{1,3}),(\d{1,3})\)$/i;

sub new {
  my $class = ref($_[0]) ? ref(shift) : shift;
  bless {%Directives}, $class;
}

$Directives{'rgba'}[0] = sub {
  my $value = _getvstr(\@_);
  my $opts = _getopts(\@_, {
    alpha => 1,
  });
  return unless defined $value;
  _serialize(_deserialize($value), -opts => $opts);
};

sub _deserialize {
  my $value = shift;
  my @rgb = (0, 0, 0);
  my $a = 1;
  $value =~ s/\s//g;
  if (my @parts = $value =~ $RE_RGB_HEX3) {
    @rgb = map {hex($_ x 2)} @parts;
  } elsif (@parts = $value =~ $RE_RGB_HEX6) {
    @rgb = map {hex($_)} @parts;
  } elsif (@parts = $value =~ $RE_RGBA) {
    $a = pop @parts;
    @rgb = @parts;
  } elsif (@parts = $value =~ $RE_RGB) {
    @rgb = @parts;
  } else {
    warn "Cannot parse color value: $value\n";
  }
  (@rgb, $a);
}

sub _serialize {
  my ($opts, @rgba) = my_opts(\@_);
  if (defined $$opts{'alpha'}) {
    $rgba[3] = $$opts{'alpha'};
  }
  sprintf 'rgba(%d,%d,%d,%0.1f)', @rgba;
}

sub _getvstr {
  my ($parser, $name, $addr) = @{$_[0]};
  $parser->get_ctx->{'collapse'} = 0;
  my $result = undef;
  if ($addr) {
    $result = $parser->get_compiled_value(\$addr);
  } else {
    $result = '';
    $parser->_invoke(text => $parser->_slurp($name), out => \$result);
  }
  $result;
}

sub _getopts {
  my ($parser, $name, $addr) = @{$_[0]};
  my $opts = my_opts(@_);
  foreach my $k (keys %$opts) {
    my $v = $opts->{$k};
    $opts->{$k} = $parser->get_compiled_value(\$v);
  }
  return $opts;
}

1;
