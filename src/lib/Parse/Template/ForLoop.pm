package Parse::Template::ForLoop;
use strict;
our $VERSION = 0;

use Perl::Module;
use Error::Logical;
use Data::Hub::Util qw(:all);
use Error::Logical;

# Note that options passed to ce:for persist and are available through the 
# context loop variable

sub new {
  my $class = ref($_[0]) ? ref(shift) : shift;
  my $self = bless {}, $class;
  $$self{'parser'} = shift;
  $$self{'args'} = \@_;
  $$self{'meta'} = {};
  for ('from', 'of', 'new') {
    if (my $var = $self->shift_arg($_)) {
      $$self{'parser'}->dequote(\$var); # $var new reflects found location
      $$self{'meta'}{$_} = $var;
    }
  }
  $self;
}

sub compile {
  my $self = shift;
  my $for_args = $$self{'parser'}->_eval_for_parse_args(@{$$self{'args'}});
  my $bundle = undef;
  if (my $from = $$self{'meta'}{'from'}) {
    # Selecting items from a pre-defined set
    my $set = $$self{'parser'}->get_value(\$from);
    $set = curry(&$set()) if isa($set, 'CODE');
    my $criteria = $$for_args{'targets'};
    my $items = [];
    my $length = 0;
    foreach my $criterion (@$criteria) {
      $length++;
      my $subset = Data::Hub::Subset->new();
      my $selected_keys = curry($$self{'parser'}->get_value(\$criterion)) or next;
      my $i = 0; # Index into selector-list
      for ($selected_keys->values) {
        $$subset{$i++} = $set->_get_value($_) if $set;
      }
      push @$items, {
        'is_static' => 0,
        'addr' => $criterion,
        'item' => $subset,
      };
    }
    $bundle = {
      'length' => $length,
      'items' => $items,
    };
  } else {
    $bundle = $$self{'parser'}->_eval_for_fetch_items($$for_args{'targets'});
  }
  my $result = $$self{'parser'}->_eval_for_exec($for_args, $bundle, $self);
  return $result;
}

sub shift_arg {
  my $self = shift;
  my $name = shift;
  my $result = undef;
  my $args = $$self{'args'};
  for (my $i = 0; $i < @$args; $i++) {
    my $arg = $args->[$i];
    if ($arg eq $name) {
      $result = $args->[$i+1];
      $$self{'parser'}->get_value(\$result);
      splice @$args, $i, 2;
      $i--;
    }
  }
  return $result;
}

sub on_begin {
  #my $self = shift;
  #my ($struct, $result) = @_;
}

sub on_each {
  #my $self = shift;
  #my ($key, $result) = @_;
}

sub on_end {
  #my $self = shift;
  #my ($struct, $result) = @_;
}

1;
