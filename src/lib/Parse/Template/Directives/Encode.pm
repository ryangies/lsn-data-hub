package Parse::Template::Directives::Encode;
use strict;
our $VERSION = 0;

use Perl::Module;
use Error::Logical;
use Data::Hub::Util qw(:all);
use HTML::Entities qw(encode_entities decode_entities encode_entities_numeric);

our %Directives;

sub new {
  my $class = ref($_[0]) ? ref(shift) : shift;
  bless {%Directives}, $class;
}

$Directives{'*'}[0] = sub {
  my $opts = _getopts(\@_, {
    ncr => "'.'",
    as_hex => 0,
    no_compile => 0,
  });
  my $value = _getvstr(@_, -opts => $opts);
  return '' unless defined $value;
  if (my $chars = $$opts{ncr}) {
    my $format = $$opts{as_hex} ? '&#x%X;' : '&#%d;';
    $value =~ s/($chars)/sprintf($format,ord($1))/eg;
  }
  $_[0]->get_ctx->{collapse} = 0;
  $value;
};

$Directives{'html'}[0] = sub {
  my $opts = _getopts(\@_, {
    ncr => undef,
    no_compile => 0,
  });
  my $value = _getvstr(@_, -opts => $opts);
  return '' unless defined $value;
  my $chars = $$opts{ncr};
  encode_entities($value, $chars);
  $_[0]->get_ctx->{collapse} = 0;
  $value;
};

$Directives{'xml'}[0] = sub {
  my $opts = _getopts(\@_, {
    ncr => undef,
    no_compile => 0,
  });
  my $value = _getvstr(@_, -opts => $opts);
  return '' unless defined $value;
  my $chars = $$opts{ncr};
  decode_entities($value); # re-encode char entities as numeric
  encode_entities_numeric($value, $chars);
  $_[0]->get_ctx->{collapse} = 0;
  $value;
};

sub _getvstr {
  my ($opts, @args) = my_opts(\@_);
  my ($parser, $name, $addr) = @args;
  my $result = undef;
  if ($addr) {
    $result = $$opts{'no_compile'}
      ? $parser->get_value(\$addr)
      : $parser->get_compiled_value(\$addr);
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
