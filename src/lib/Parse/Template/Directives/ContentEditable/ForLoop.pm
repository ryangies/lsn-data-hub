package Parse::Template::Directives::ContentEditable::ForLoop;
use strict;
our $VERSION = 0;

use Perl::Module;
use Error::Logical;
use Data::Hub::Util qw(:all);
use Error::Logical;
use base qw(Parse::Template::ForLoop);

sub on_begin {
  my $self = shift;
  my ($struct, $result) = @_;
  my $addr = $$struct{'addr'};
# my $item = $$struct{'item'};
# throw Error::Logical 'ce:for can only operate on arrays'
#   unless isa($item, 'ARRAY');
  my @params = ("ds='$addr'");
  my $meta = $$self{'meta'};
  push @params, map {"$_='$$meta{$_}'"} keys %$meta;
  $$self{'parser'}->is_editing and
    $$result .= '<!--ce:begin="' . join(';', @params) . "\"-->\n";
}

sub on_each {
  my $self = shift;
  my ($key, $result) = @_;
  $$self{'parser'}->is_editing and
    $$result .= "<!--ce:item=\"key='$key';\"-->";
}

sub on_end {
  my $self = shift;
  my ($struct, $result) = @_;
  $$self{'parser'}->is_editing and
    $$result .= "<!--ce:end-->";
}

1;
