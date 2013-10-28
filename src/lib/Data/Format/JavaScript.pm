package Data::Format::JavaScript;
use strict;
our $VERSION = 0;

use Perl::Module;
use Error::Programatic;
use base qw(Exporter);

our @EXPORT_OK = qw(
  js_format
  js_format_key
  js_format_value
  js_format_string
  js_format_lsn
);

our %EXPORT_TAGS = (all=>[@EXPORT_OK]);

sub js_format {
  my ($item) = @_;
  if (!defined $item) {
    return q("");
  } elsif (isa($item, 'HASH')) {
    return '{' . join(",", map {js_format_key($_) . ':' . js_format($$item{$_})}
      grep {!/^\./} keys %$item) . "}";
  } elsif (isa($item, 'ARRAY')) {
    return '[' . join(",", map {js_format($_)} @$item) . ']';
  } else {
    return js_format_value($item);
  }
}

sub js_format_lsn {
  my ($item) = @_;
  if (!defined $item) {
    return q("");
  } elsif (isa($item, 'HASH')) {
    return 'new LSN.OrderedHash(' . join(",", map {js_format_key($_) . ', ' . js_format_lsn($$item{$_})}
      grep {!/^\./} keys %$item) . ")";
  } elsif (isa($item, 'ARRAY')) {
    return 'new LSN.Array(' . join(",", map {js_format_lsn($_)} @$item) . ')';
  } else {
    return js_format_value($item);
  }
}

sub js_format_key {
  my $key = shift;
  $key =~ s/(?<!\\)(["])/\\$1/g;
  $key =~ s/\//&#x2f;/g;
  return '"' . $key . '"';
}

sub js_format_value {
  my $value = shift;
  isa($value, 'SCALAR') and $value = $$value;
  return $value if $value =~ /^(null|NaN|undefined|true|false|[0-9]|[1-9]\d+|\s*function\s*\()$/;
  return js_format_string($value);
}

sub js_format_string {
  my $value = shift;
  isa($value, 'SCALAR') and $value = $$value;
  $value =~ s/^'(null|NaN|undefined|true|false|[0-9]|[1-9]\d+)$/$1/;
  $value =~ s/([\\"])/\\$1/gm;
  $value =~ s/(\r?\n\r?|\r)/\\n/gm;
  return '"' . $value . '"';
}

1;
