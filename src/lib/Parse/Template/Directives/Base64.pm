package Parse::Template::Directives::Base64;
use strict;
our $VERSION = 0;

use Perl::Module;
use Error::Logical;
use Data::Hub::Util qw(:all);
use MIME::Base64;
use Encode qw(is_utf8);

our %Directives;

sub new {
  my $class = ref($_[0]) ? ref(shift) : shift;
  bless {%Directives}, $class;
}

$Directives{'encode'}[0] = sub {
  $_[0]->get_ctx->{'collapse'} = 0;
  my $value = _getvstr(\@_);
  return unless defined $value;
  my $octets = is_utf8($value) ? Encode::encode('UTF-8', $value) : $value;
  encode_base64($octets, '');
};

$Directives{'decode'}[0] = sub {
  $_[0]->get_ctx->{'collapse'} = 0;
  my $value = _getvstr(\@_);
  return unless defined $value;
  Encode::decode('UTF-8', decode_base64($value));
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
