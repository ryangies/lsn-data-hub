package Parse::Template::Directives::URI;
use strict;
our $VERSION = 0;

use Perl::Module;
use Error::Logical;
use Data::Hub::Util qw(:all);
use HTML::Entities qw(decode_entities encode_entities);

our %Directives;

sub new {
  my $class = ref($_[0]) ? ref(shift) : shift;
  bless {%Directives}, $class;
}

$Directives{'url'}[0] = sub {
  my $value = _getvstr(\@_);
  return unless defined $value;
  _mk_url($value);
};

$Directives{'encode'}[0] = sub {
  my $value = _getvstr(\@_);
  return unless defined $value;
  $value =~ s/([^A-Za-z0-9_~\.\-])/sprintf("%%%02X", ord($1))/eg;
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

$Directives{'urlencoded'}[0] = sub {
  my $parser = $_[0];
  my $value = _getvstr(\@_);
  return unless defined $value;
  $parser->get_ctx->{'collapse'} = 1;
  _query_escape($value);
};

sub _mk_url {
  my $value = shift or return;
  my $add_slash = $value =~ /\/$/;
  my ($uri, $query) = $value =~ /([^\?#]+)(.*)/;
  my ($prefix, $path) = $uri =~ /((?:[a-z\+]+:)?\/\/)?(.*)/;
  my @path = ();
  for (split /\//, $path) {
    $_ = '' unless defined; # retain empty path segments
    $_ = _uri_unescape($_) if $prefix; # it may already be escaped
    $_ = _uri_escape($_);
    push @path, $_;
  }
  my $suffix = @path ? join('/', @path) : '';
  my $result = $prefix || '';
  $result .= $suffix if $suffix;
  $result .= '/' if $add_slash;
  $result .= _query_escape($query) if $query;
  $result;
}

sub _uri_unescape {
  my $url = shift;
  decode_entities($url);
  $url =~ s/%([a-fA-F0-9]{2})/pack("C",hex($1))/eg;
  $url;
}

sub _uri_escape {
  my $str = shift;
  encode_entities($str, '&');
  $str =~ s/([\s"'])/sprintf("%%%02X", ord($1))/eg;
  $str;
}

sub _query_escape {
  my $query = shift;
  my @parts = split /[&;]/, decode_entities($query);
  my @result = ();
  for (@parts) {
    s/([\s"'])/sprintf("%%%02X", ord($1))/eg;
    push @result, $_;
  }
# This is for when the URI is an r-val within another URI's query.
# TODO - enable this behavior via an option (or another directive)
#        and at that time take care of also encoding the hash.
# join '&amp;', @result;
  join '&', @result;
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

1;
