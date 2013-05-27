package Data::Hub::Courier;
use strict;
our $VERSION = 0.1;

use Perl::Module;
use Perl::Compare qw(compare);
use Error::Programatic;
use Error::Simple;
use Data::Hub::Subset;
use Data::Hub::ExpandedSubset;
use Data::Hub::Util qw(:all);
use Data::Hub::Query;

# str
# list
# get
# set
# delete
# append
# prepend
# iterate
# walk
# length
# keys
# values
# to_string
# _get
# _get_recursive
# _get_value
# _vivify
# _set_value
# _delete_value
# _append
# _prepend


sub str {
  to_string(get(@_));
}

sub to_string {
  my $s = $_[0];
  isa($_[0], 'HASH') and $s = scalar %{$_[0]};
  isa($_[0], 'ARRAY') and $s = scalar @{$_[0]};
  isa($s, 'SCALAR') ? $$s : $s;
}

sub get {
  my ($struct, $addr_str) = @_;
  return if (!defined($addr_str) || ($addr_str eq ''));
  my @addr = addr_split($addr_str);
  return $struct unless @addr; # '/' will split to an empty array
  while (defined $struct && @addr) {
    throw Error::Programatic "Attempt to eval while traversing: $addr_str"
      if isa($struct, 'CODE');
    my $k = shift @addr;
    $struct = _get($struct, $k);
  }
  @addr ? undef : $struct;
}

# sub get_concrete {
#   my ($struct, $addr_str) = @_;
#   return if (!defined($addr_str) || ($addr_str eq ''));
#   my @addr = addr_split($addr_str);
#   return $struct unless @addr; # '/' will split to an empty array
#   while (defined $struct && @addr) {
#     throw Error::Programatic "Attempt to eval while traversing: $addr_str"
#       if isa($struct, 'CODE');
#     my $k = shift @addr;
#     $struct = _get_value($struct, $k);
#   }
#   @addr ? undef : $struct;
# }

sub _get {
  !defined $_[1] || $_[1] eq ''     ? $_[0]
  : $_[1] =~ RE_ABSTRACT_KEY()      ? Data::Hub::Query::query($_[0], $_[1])
  : isa($_[0], 'Data::Hub::Subset') ? $_[0]->_get($_[1])
# : can($_[0], '_get_value')        ? $_[0]->_get_value($_[1])
  : _get_value($_[0], $_[1]);
}

sub _get_recursive {
  my $struct = shift;
  my $root = shift;
  $root = '' unless defined $root;
  $root and $root .= '/';
  my $subset = Data::Hub::ExpandedSubset->new();
  iterate($struct, sub {
    my ($k, $v) = (shift, shift);
    if (isa($v, 'ARRAY') || isa($v, 'HASH')) {
      if (isa($v, FS('Node')) && !isa($v, FS('Directory'))) {
        # Do not recurse into filesystem objects which are not directories
        $subset->{"$root$k"} = $v;
      } elsif (Data::Hub::Courier::length($v) > 0) {
        _get_recursive($v, "$root$k")->iterate(sub {
          $subset->{$_[0]} = $_[1];
        });
      } else {
        $subset->{"$root$k"} = $v;
      }
    } else {
      $subset->{"$root$k"} = $v;
    }
    
  });
  $subset;
}

sub list {
  my $struct = shift;
  my $value = get($struct, @_);
  $value = Data::Hub::Container->new([]) unless defined $value;
  return $value if (isa($value, 'ARRAY'));
  return $value if (isa($value, 'Data::Hub::Subset'));
  Data::Hub::Container->new([$value]);
}

sub _get_value {
  isa($_[0], 'HASH')
    ? $_[0]->{$_[1]}
    : isa($_[0], 'ARRAY')
      ? defined $_[1] && $_[1] =~ /^\d+$/
        ? $_[0]->[$_[1]]
        : undef
      : undef;
}

# Set

sub set {
  my ($struct, $addr_str, $value) = @_;
  my @addr = addr_split($addr_str);
  my $last_key = pop @addr;
  my $parent = @addr ? _vivify($struct, \@addr, $last_key) : $struct;
  _set_value($parent, $last_key, $value);
}

sub _vivify {
  my ($struct, $addr, $last_key) = @_;
  my $key = shift @$addr;
  my $node = _get($struct, $key);
  unless (defined $node) {
    die "Cannot vivify abstract key" if is_abstract_key($key);
    if (can($struct, 'vivify')) {
      $node = $struct->vivify($key);
    } else {
      my $next_key = @$addr ? $addr->[0] : $last_key;
      my $child = ($next_key =~ /^0\/?$/ || $next_key eq '<next>') ? [] : {};
      $node = _set_value($struct, $key, $child);
    }
  }
  (defined $node && @$addr) ? _vivify($node, $addr, $last_key) : $node;
}

sub _set_value {
  isa($_[0], 'HASH') and return $_[0]->{$_[1]} = $_[2];
  return unless isa($_[0], 'ARRAY');
  if ($_[1] eq '<next>') {
    return push @{$_[0]}, $_[2];
  } else {
    {
      no warnings 'numeric';
      throw Error::Programatic('Invalid array index') unless int($_[1]) eq $_[1];
    }
    return $_[0]->[$_[1]] = $_[2];
  }
}

# Delete

sub delete {
  my ($struct, $addr_str, $value) = @_;
  my @addr = addr_split($addr_str);
  my $last_key = pop @addr;
  return unless defined $last_key;
  my $parent = @addr ? get($struct, join('/', @addr)) : $struct;
  return unless defined $parent;
  if (is_abstract_key($last_key)) {
    $parent = curry($parent);
    my $subset = $parent->get($last_key);
    my @keys = $subset->keys();
    if (isa($parent, 'ARRAY')) {
      for (my $i = 0; $i < @keys; $i++) {
        my $key = $keys[$i];
        my $idx = addr_shift($key);
        $idx -= $i;
        $parent->delete($key ? "$idx/$key" : $idx);
      }
    } elsif (isa($parent, 'HASH')) {
      $parent->delete($_) for @keys;
    }
  } else {
    _delete_value ($parent, $last_key);
  }
}

sub _delete_value {
  isa($_[0], 'HASH') and return delete $_[0]->{$_[1]};
  isa($_[0], 'ARRAY') and return splice @{$_[0]}, $_[1], 1;
  undef;
}

# ------------------------------------------------------------------------------
# append - Append an item on to the container
# ------------------------------------------------------------------------------
#|test(match,abc) # Append to an array
#|my $h = {g=>[qw(a b)]};
#|Data::Hub::Courier::append($h, '/g', 'c');
#|join('', @{$$h{g}});
# ------------------------------------------------------------------------------
#|test(match,abc) # Append to a hash
#|my $h = {g=>Data::OrderedHash->new(a => 1, b => 2)};
#|Data::Hub::Courier::append($h, '/g', c => 3);
#|join('', keys %{$$h{g}});
# ------------------------------------------------------------------------------
#|test(match,abc) # Append to a scalar
#|my $h = {g=>str_ref('ab')};
#|Data::Hub::Courier::append($h, '/g', 'c');
#|${$$h{g}};
# ------------------------------------------------------------------------------

sub append {
  my ($struct, $addr_str) = (shift, shift);
  my @addr = addr_split($addr_str);
  my $last_key = pop @addr;
  my $parent = @addr ? _vivify($struct, \@addr, $last_key) : $struct;
  my $node = _get($parent, $last_key);
  $node ||= _set_value($parent, $last_key, []);
  ref($node)
    ? _append($node, @_)
    : _set_value($parent, $last_key, join('', $node, @_));
}

sub _append {
  my $struct = shift;
  if (isa($struct, 'HASH')) {
    while (@_) {
      my ($k, $v) = (shift, shift);
      $struct->{$k} = $v; # OrderedHash appends by default
    }
  } elsif (isa($struct, 'ARRAY')) {
     push @{$struct}, @_;
  } elsif (isa($struct, 'SCALAR')) {
     ${$struct} = join('', ${$struct}, @_);
  } else {
    undef;
  }
}

# ------------------------------------------------------------------------------
# prepend - Prepend an item on to the container
# ------------------------------------------------------------------------------
#|test(match,abc) # Prepend to an array
#|my $h = {g=>[qw(b c)]};
#|Data::Hub::Courier::prepend($h, '/g', 'a');
#|join('', @{$$h{g}});
# ------------------------------------------------------------------------------
#|test(match,abc) # Prepend to a hash
#|my $h = {g=>Data::OrderedHash->new(b => 2, c => 3)};
#|Data::Hub::Courier::prepend($h, '/g', a => 1);
#|join('', keys %{$$h{g}});
# ------------------------------------------------------------------------------
#|test(match,abc) # Prepend to a scalar
#|my $h = {g=>str_ref('bc')};
#|Data::Hub::Courier::prepend($h, '/g', 'a');
#|${$$h{g}};
# ------------------------------------------------------------------------------

sub prepend {
  my ($struct, $addr_str) = (shift, shift);
  my @addr = addr_split($addr_str);
  my $last_key = pop @addr;
  my $parent = @addr ? _vivify($struct, \@addr, $last_key) : $struct;
  my $node = _get($parent, $last_key);
  $node ||= _set_value($parent, $last_key, []);
  ref($node)
    ? _prepend($node, @_)
    : $parent->_set_value($last_key, join('', @_, $node));
}

sub _prepend {
  my $struct = shift;
  if (isa($struct, 'HASH')) {
    throw Error::Programatic('Method prepend not found: ' . ref($struct))
      unless can($struct, 'prepend');
    while (@_) {
      my ($k, $v) = (shift, shift);
      $struct->prepend($k, $v);
    }
  } elsif (isa($struct, 'ARRAY')) {
     unshift @{$struct}, @_;
  } elsif (isa($struct, 'SCALAR')) {
     ${$struct} = join('', @_, ${$struct});
  } else {
    undef;
  }
}

sub iterate {
  my ($struct, $code) = @_;
  my @kv_pairs = ();
  my $sig = -1;
  if (isa($struct, 'HASH')) {
    $sig = 1;
    for (CORE::keys %$struct) {
      &$code($_, $$struct{$_}, \$sig);
      last unless $sig;
    }
  } elsif (isa($struct, 'ARRAY')) {
    $sig = 1;
    my $i = 0;
    for (@$struct) {
      &$code($i++, $_, \$sig);
      last unless $sig;
    }
  };
  $sig;
}

sub walk {
  my $struct = shift or throw Error::MissingArg;
  my $code = shift or throw Error::MissingArg;
  my $prefix = shift;
  my $depth = shift || 0;
  iterate($struct, sub {
    my ($k, $v) = @_;
    my $addr = defined($prefix) ? "$prefix/$k" : $k;
    &$code($k, $v, $depth, $addr, $struct);
    if (isa($v, 'ARRAY') || isa($v, 'HASH')) {
      walk($v, $code, $addr, $depth + 1);
    }
  });
}

sub length {
  my ($struct) = @_;
  isa($struct, 'HASH') and return scalar(grep ! /^\./, CORE::keys %{$struct});
  isa($struct, 'ARRAY') and return scalar(@{$struct});
  undef;
}

sub keys {
  my ($struct, $idx) = @_;
  if (defined $idx) {
    my @keys = isa($struct, 'HASH')
      ? CORE::keys %{$struct}
      : isa($struct, 'ARRAY')
        ? (0 .. $#$struct)
        : undef;
    return $keys[$idx];
  } else {
    isa($struct, 'HASH') and return CORE::keys %{$struct};
    isa($struct, 'ARRAY') and return (0 .. $#$struct);
    undef;
  }
}

sub values {
  my ($struct, $idx) = @_;
  if (defined $idx) {
    my @values = isa($struct, 'HASH')
      ? CORE::values %{$struct}
      : isa($struct, 'ARRAY')
        ? @$struct
        : undef;
    return $values[$idx];
  } else {
    isa($struct, 'HASH') and return CORE::values %{$struct};
    isa($struct, 'ARRAY') and return @$struct;
    undef;
  }
}

1;

__END__

=pod:summary Courier services for hierarchical data addresses

=pod:synopsis

=test(match)

  use Data::Hub::Courier;
  my $h = {
    A => {
      I => [
        'Hello'
      ],
    },
  };
  Data::Hub::Courier::set($h, '/A/I/1', 'World!');
  my $a = Data::Hub::Courier::get($h, '/A/I');
  join ' ', @$a;

=result

  Hello World!

=cut
