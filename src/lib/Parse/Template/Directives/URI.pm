package Parse::Template::Directives::URI;
use strict;
our $VERSION = 0;

use Perl::Module;
use Error::Logical;
use Data::Hub::Util qw(:all);

our %Directives;

sub new {
  my $class = ref($_[0]) ? ref(shift) : shift;
  bless {%Directives}, $class;
}

$Directives{'encode'}[0] = sub {
  my $value = _getvstr(\@_);
  return unless defined $value;
  $value =~ s/([^A-Za-z0-9_])/sprintf("%%%02X", ord($1))/eg;
  $value;
};

$Directives{'decode'}[0] = sub {
  my $value = _getvstr(\@_);
  return unless defined $value;
  $value =~ tr/+/ /;
  $value =~ s/%([a-fA-F0-9]{2})/pack("C",hex($1))/eg;
  utf8::decode($value);
  $value;
};

sub _getvstr {
  my ($parser, $name, $addr) = @{$_[0]};
  my $result = undef;
  if ($addr) {
    $result = $parser->get_compiled_value(\$addr);
  } else {
    $result = '';
    $parser->_invoke(text => $parser->_slurp($name), out => \$result);
  }
  $result;
}

1;
