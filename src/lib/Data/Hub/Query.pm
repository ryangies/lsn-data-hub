package Data::Hub::Query;
use strict;
our $VERSION = 0;

use Perl::Module;
use Perl::Compare qw(compare);
use Error::Logical;
use Data::Hub::Subset;
use Data::Hub::Util qw(:all);
use Data::Hub::Courier;

our %Query_Handler = (); # implementation methods
our %Manip = (); # true for those which only manipulate an existing structure

sub RE_SPLIT { qr/^((?:\\[\{\|]|[^\{\|])+)?\|?(?:\{(.*)\})?$/ };

sub query {
  my ($struct, $term) = @_;
  my ($static, $query) = $term =~ RE_SPLIT();
#warnf "XXX: %-30s %-20s %s\n", $term, $static||'undef', $query||'undef';
  if (defined $static && $query) {
    # Filtering an item
    $struct = Data::Hub::Courier::_get($struct, $static);
    $struct = _query($struct, $query);
  } elsif (defined $static) {
    $struct = _query_expansion($struct, $static);
  } elsif (defined $query) {
    # Manipulations operate as a refinement or selection of the structure
    # and we must make that determination before passing it on to _query.
    my $c = substr $query, 0, 1;
    my $h = $Query_Handler{$c};
    goto &_query_legacy unless $h;
    $struct = $struct->_expand if !$Manip{$c} && can($struct, '_expand');
    $struct = _query($struct, $query);
  } else {
    $struct = undef;
  }
  $struct;
}

#
# query
# query_1}|{query_2}|{query_n
#
# Note that adjacent quieries are joined by }|{, split on that sequence, and no 
# consideration has been made to support the case where that sequence is used
# in a query's rval.
#
sub _query {
  my $struct = $_[0];
  my @chain = split /\}\|\{/, $_[1]; # this could be part of a query term...
  for (@chain) {
    my $c = substr $_, 0, 1;
    my $h = $Query_Handler{$c};
    throw Error::Programatic "No query handler defined for: $c" unless $h;
    my $q = substr $_, 1;
    $struct = &$h($struct, $q);
  }
  $struct;
}

#
# *
# **
# *.xyz
# xyz.*
# x*.yz
#
sub _query_expansion {
  $_[1] eq '**' and return Data::Hub::Courier::_get_recursive($_[0]);
  $_[1] eq '*' and return Data::Hub::Subset->new($_[0]);
# $_[1] eq '*' and return Data::Hub::ExpandedSubset->new($_[0]);
  $_[1] =~ s/(?<!\\)\./\\./g; # TODO escape other character classes
  $_[1] =~ s/(?<!\\)\*/.*/g;
  _query($_[0], '?(=~):' . '^' . $_[1] . '$');
}

# {:first}
# {:last}
# {:reverse}
# {:sort}
# {:sort $key}
# {:rsort}
# {:rsort $key}
sub _query_manip {
  my ($struct, $crit) = @_;
  my @expr = $crit =~ /^(reverse|sort|rsort|first|last)(?:\s+([^\s]+))?$/;
  my $opr = shift @expr;
  my $ordered = Data::Hub::Subset->new();
  $struct = curry($struct);
  if ($opr =~ /sort$/) {
    if (my $skey = shift @expr) {
      $ordered->{$_} = Data::Hub::Courier::_get_value($struct, $_) for sort {
        my $a_struct = Data::Hub::Courier::_get_value($struct, $a);
        my $b_struct = Data::Hub::Courier::_get_value($struct, $b);
        my $a_value = Data::Hub::Courier::_get_value($a_struct, $skey);
        my $b_value = Data::Hub::Courier::_get_value($b_struct, $skey);
        $a_value cmp $b_value;
      } $struct->keys;
    } else {
      $ordered->{$_} = Data::Hub::Courier::_get_value($struct, $_) for sort $struct->keys;
    }
  } elsif ($opr eq 'first') {
    my @values = $struct->values();
    return shift @values;
  } elsif ($opr eq 'last') {
    my @values = $struct->values();
    return pop @values;
  } else {
    $ordered = $struct;
  }
  if ($opr =~ /^reverse|rsort$/) {
    my @keys = $ordered->keys;
    my $result = Data::Hub::Subset->new();
    $result->{$_} = $ordered->_get_value($_) for reverse @keys;
    return $result;
  } else {
    return $ordered;
  }
}

# {-d}
# {-?:directory}
# {-?:~file-}
sub _query_type {
  my ($struct, $crit) = @_;
  my $result = Data::Hub::Subset->new();
  my @expr = $crit =~ /^([^\-\s\d])(?:\:([^\s]+))?$/;
  my $type = $expr[0] eq '?'
    ? $expr[1]
    : $TYPEOF_ALIASES{$expr[0]};
  throw Error::Logical "undefined type query: $expr[0]" unless defined $type;
  my $comparator = $type =~ s/^([=!]~)// ? $1 : 'eq';
  Data::Hub::Courier::iterate($struct, sub {
    Data::Hub::Courier::_set_value($result, @_)
      if compare($comparator, typeof(@_), $type);
  });
  $result;
}

# ------------------------------------------------------------------------------
# _query_compare - Query a structure for values which match the given criteria
# _query_compare $struct, $criteria
#
# The general form is:
#
#   {?[!]key(opr):val}
#
# The leading C<!> negation symbol, when present, inverts the result of the
# comparson.
#
# However both C<opr> and C<key> are optional.
#
#   {?(opr):val}    # Without the key, all values are compared and a subset of
#                   # matches is returned.
#
#   {?key:val}      # Without the operator, a single value (first match) is 
#                   # returned instead of a subset.
#
#   {?:val}         # Without the key or operator, a single value (first match)
#                   # is returned. All values are compared.
#
#   {?key}          # With only the key, the result is items where the value
#                   # at that key is logically true.
#
# When the C<opr> is omitted, the 'eq' operator is used in comparisons.
#
# If C<key> contains C<( ) :> those character must be escaped with a backslash.
#
# If C<val> contains C<}> it must be escaped with a backslash.
#
# The operators available for C<opr> are those implemented by L<Perl::Compare>:
#
#   Perl Operators (see L<perlop>)
#
#     eq  =~  ==
#     ne  !~  !=
#     lt      <
#     le      <=
#     gt      >
#     ge      >=
#
#   Extended operators
#
#     eqic    # Same as 'eq' however is case insensitive
#     neic    # Same as 'ne' however is case insensitive
#     mod     # Modulus, e.g., {?age(mod):30} is true for ages of 30,60,90,...
#
# The key may contain spaces:
#
#   /users/{?first name(=~):Ryan} # List all users with a first name of 'Ryan'
#
# Random examples:
#
#   {?(=~):[A-Z]}             # set of all values whose key has an upper-case letter
#   {?id:1234}                # the first value whose id is 1234
#   {?id(eq):1234}            # set of all values whose id is 1234
#   {?id(==):1234}            # set of all values whose id is 1234 (numerically)
#   {?first name(eq):Ryan}    # set of all users whose 'first name' is Ryan
#   {?group(=~):aeiou}        # set of all values whose group contains a vowel
#   {?!disabled}              # set of all values which are not 'disabled'
#
#
# TODO - Query before expansion
#
#   What we want is to say; /data.hf/**/{?schema(eq):product}
#   and have the subset expansion stop at the point where an item with 
#   a key of 'schema' is equal to 'product'. This however is code which
#   slurps backward $c slashes from an expanded key:
#
#   my $c = defined $key ? $key =~ tr'/'' : 0;
#   my $i = rindex $_[0], '/';
#   for (my $j = 0; $i > -1 && $j < $c; $j++) {
#     $i = rindex $_[0], '/', $i - 1;
#   }
#   my $k = $i > -1 ? substr $_[0], $i + 1 : $_[0];
#
# ------------------------------------------------------------------------------

sub _query_compare {
  my ($struct, $crit) = @_;
  my ($negate, $key, $opr, $val) =
    $crit =~ /^(!?)((?:(?<=\\)[():]|[^():])*)(?:\((.{1,4})\))?:?(.+)?/;
  $val = '' unless defined $val;
  undef $key if defined $key && $key eq '';
  $key =~ s/\\([:()_])/$1/g if defined $key; # unescape
  my $truth = !$negate;
#warn "Truth=$truth, $crit\n";
#warn "Query for: $key $opr $val\n";
  if (defined $opr) {
    # Return a subset of matches
    my $result = Data::Hub::Subset->new();
    if (!defined $key) {
      # Query the key
      Data::Hub::Courier::iterate($struct, sub {
        $result->_set_value(@_) unless $truth xor compare($opr, $_[0], $val);
      });
    } elsif ($key eq '*') {
      # Query all values
      if ($truth) {
        Data::Hub::Courier::iterate($struct, sub {
          $result->_set_value(@_) if compare($opr, $_[1], $val);
        });
      }
    } else {
      # Query a property of each value
      Data::Hub::Courier::iterate($struct, sub {
        my $vv = Data::Hub::Courier::get($_[1], $key);
#warn "Compare: $vv $opr $val";
        $result->_set_value(@_) unless $truth xor compare($opr, $vv, $val);
      });
    }
    return $result;
  } elsif (defined $key && $val eq '') {
    # Query for items where a subkey is logically true or false. Keys which do
    # not exist are treated as false.
    my $result = Data::Hub::Subset->new();
    Data::Hub::Courier::iterate($struct, sub {
      my $vv = Data::Hub::Courier::get($_[1], $key);
      my $pass = $truth ? !!$vv : !$vv;
#warnf "Compare: `%s` is logically %s => %s\n", $key, $truth ? 'true' : 'false', $pass ? 'yes' : 'no';
      $result->_set_value(@_) if $pass;
    });
    return $result;
  } else {
    # Return the first match
    my $r_val = undef;
    my $r_key = undef;
    if (!defined $key) {
      # Query the key
      foreach my $k (Data::Hub::Courier::keys($struct)) {
        next unless defined $k && !($truth xor (addr_name($k) eq $val));
        $r_key = $k;
        $r_val = Data::Hub::Courier::_get_value($struct, $k);
        last;
      }
    } elsif ($key eq '*') {
      # Query all values
      foreach my $k (Data::Hub::Courier::keys($struct)) {
        $r_key = $k;
        $r_val = Data::Hub::Courier::_get_value($struct, $k);
        last if defined $r_val && !($truth xor ($r_val eq $val));
        undef $r_val;
        undef $r_key;
      }
    } else {
      # Query a property of each value
      foreach my $k (Data::Hub::Courier::keys($struct)) {
        $r_key = $k;
        $r_val = Data::Hub::Courier::_get_value($struct, $k);
        my $vv = Data::Hub::Courier::get($r_val, $key);
        last if defined $vv && !($truth xor ($vv eq $val));
        undef $r_val;
        undef $r_key;
      }
    }
    # Wrap the first match in a subset if already in a subset. This maintains
    # the knowledge of the matched key.
#   if (isa($struct, 'Data::Hub::Subset')) {
#     my $r = Data::Hub::Subset->new();
#     $r->_set_value($r_key, $r_val) if defined $r_val;
#     return $r;
#   } else {
      return $r_val;
#   }
  }
}

# {@10}         Just the 11th item
# {@10,1}       The 11th and 2nd item
# {@13-15}      The 14th through the 16th items
# {@13-}        From the 14th on
# {@10,1,13-15} The 11th, 2nd, and 14th through 16th items
sub _query_position {
  my ($struct, $crit) = @_;
  my $result = Data::Hub::Subset->new();
  my @segments = split ',', $crit;
  my $p = 0;
  for (@segments) {
    if (my ($b, $e) = /(\d+)-(\d+)?/) {
      !defined $e and $e = Data::Hub::Courier::length($struct) - 1;
      splice @segments, $p, 1, ($b .. $e);
    }
    $p++;
  }
  my $idx = 0;
  Data::Hub::Courier::iterate($struct, sub {
    Data::Hub::Courier::_set_value($result, @_)
        if defined grep_first {$_ == $idx} @segments;
    $idx++;
  });
  $result;
}

$Manip{':'} = 1;
$Manip{'@'} = 1;

$Query_Handler{':'} = \&_query_manip;
$Query_Handler{'-'} = \&_query_type;
$Query_Handler{'?'} = \&_query_compare;
$Query_Handler{'@'} = \&_query_position;

sub _query_legacy {
  my ($struct, $criteria) = @_;
  my $result = Data::Hub::Subset->new();
  my @expr = ();
  $criteria =~ s/^{//;
  $criteria =~ s/}$//;
  if (@expr = $criteria =~ /$PATTERN_QUERY_SUBKEY/) {
    $struct = $struct->_expand if can($struct, '_expand');
#warn "SUBKEY QUERY:", @expr, "\n";
    # e.g., {id <= 100}
    Data::Hub::Courier::iterate($struct, sub {
      my ($k, $v) = @_;
      my $vv = Data::Hub::Courier::get($v, $expr[0]);
      Data::Hub::Courier::_set_value($result, $k, $v) if compare($expr[1], $vv, $expr[2]);
    });
  } elsif (@expr = $criteria =~ /$PATTERN_QUERY_RANGE/) {
#warn "RANGE QUERY:", @expr, "\n";
    # e.g., {10,1,13-15}
    my @segments = split ',', $expr[0];
    my $p = 0;
    for (@segments) {
      if (my ($b, $e) = /(\d+)-(\d+)/) {
        splice @segments, $p, 1, ($b .. $e);
      }
      $p++;
    }
    my $idx = 0;
    Data::Hub::Courier::iterate($struct, sub {
      Data::Hub::Courier::_set_value($result, @_) if defined grep_first {$_ == $idx} @segments;
      $idx++;
    });
#DEPREICATED:BEGIN
    # When one item is requested return only that item
    if (@segments == 1 && $segments[0] !~ /-/) {
      my @values = $result->values();
      $result = $values[0];
    }
#DEPRICATED:END
  } elsif (@expr = $criteria =~ /$PATTERN_QUERY_VALUE/) {
#warn "VALUE QUERY:", @expr, "\n";
    # e.g., {=~ '[A-Z]'}
    $struct = $struct->_expand if can($struct, '_expand');
    Data::Hub::Courier::iterate($struct, sub {
      Data::Hub::Courier::_set_value($result, @_) if compare($expr[0], $_[1], $expr[1]);
    });
  } elsif (@expr = $criteria =~ /$PATTERN_QUERY_KEY/) {
#warn "KEY QUERY:", @expr, "\n";
    # e.g., {USER_}
    $struct = $struct->_expand if can($struct, '_expand');
    $expr[0] =~ s/\\([{}])/$1/g;
    my $comparator = $expr[0] =~ s/^\!// ? '!~' : '=~';
    Data::Hub::Courier::iterate($struct, sub {
      compare($comparator, $_[0], $expr[0]) and Data::Hub::Courier::_set_value($result, @_);
    });
  }
  $result;
}

1;

__END__

=pod:summary Implementation of queries for L<Data::Hub::Courier>

=pod:description

=test(!abort)

  # This test case simply sets up the test data and subroutine for running
  # subsequent test queries.

  use Data::Hub::Util qw(:all);
  use Data::Format::Hash qw(hf_format hf_parse);
  use Data::OrderedHash;

  my $ttt_data = curry(hf_parse('

    array => @{
      a
      b
      c
      ab
      abc
    }

    hash => %{
      a => Alpha
      b => Beta
      c => Charlie
    }

    array_of_hashes => @{
      %{
        name => a
        text => Alpha
      }
      %{
        name => b
        text => Beta
      }
      %{
        name => c
        text => Charlie
      }
    }

    hash_of_hashes => %{
      a => %{
        text => Alpha
        num => 3
      }
      b => %{
        text => Beta
        num => 2
      }
      c => %{
        text => Charlie
        num => 1
      }
    }

  '));

  # The test data is curried to provide the get method of Data::Hub::Courier

  sub ttt_query {
    my $q = shift;
    my $r = $ttt_data->get($q);
    return unless defined $r;
    my $ref = ref($r);
    $ref ? hf_format({$ref => $r}) : $r;
  }

=cut

Testing arrays

=test(!defined)

  # Use an invalid index
  ttt_query('array/{?:fail}');

=test(!defined)

  # Get the value whose value is ''
  ttt_query('array/{?:}');

=test(match)

  # Get the value whose key is eq 0
  ttt_query('array/{?:0}');

=result

  a

=test(match)

  # Get the value whose key is == 0
  ttt_query('array/{?(==):0}');

=result

  Data::Hub::Subset => %{
    0 => a
  }

=test(match)

  # Get all items whose key is >= 2
  ttt_query('array/{?(>=):2}');

=result

  Data::Hub::Subset => %{
    2 => c
    3 => ab
    4 => abc
  }

=test(match)

  # Get the value whose value is 'a'
  ttt_query('array/{?*:a}');

=result

  a

=test(match)

  # Get all items whose value is eq 'a'
  ttt_query('array/{?*(eq):a}');

=result

  Data::Hub::Subset => %{
    0 => a
  }

=test(match)

  # Get all items whose value is =~ /a/
  ttt_query('array/{?*(=~):a}');

=result

  Data::Hub::Subset => %{
    0 => a
    3 => ab
    4 => abc
  }

=cut

Testing hashes

=test(match)

  # Get the value whose key is eq 'a'
  ttt_query('hash/{?:a}');

=result

  Alpha

=test(match)

  # Get the value whose value is eq 'Alpha'
  ttt_query('hash/{?*:Alpha}');

=result

  Alpha

=test(match)

  # Get all items whose value is eq 'Alpha'
  ttt_query('hash/{?*(eq):Alpha}');

=result

  Data::Hub::Subset => %{
    a => Alpha
  }

=test(match)

  # Get all items whose value is =~ /a$/
  ttt_query('hash/{?*(=~):a$}');

=result

  Data::Hub::Subset => %{
    a => Alpha
    b => Beta
  }

=cut

Testing arrays of hashes

=test(match)

  # Get the value whose key is eq 0
  ttt_query('array_of_hashes/{?:0}');

=result

  Data::OrderedHash => %{
    name => a
    text => Alpha
  }

=test(match)

  # Get the value whose name is eq 'a'
  ttt_query('array_of_hashes/{?name:a}');

=result

  Data::OrderedHash => %{
    name => a
    text => Alpha
  }

=test(match)

  # Get all items whose name is eq 'a'
  ttt_query('array_of_hashes/{?name(eq):a}');

=result

  Data::Hub::Subset => %{
    0 => %{
      name => a
      text => Alpha
    }
  }

=test(match)

  # Get all items whose name is =~ /a|b/
  ttt_query('array_of_hashes/{?name(=~):a|b}');

=result

  Data::Hub::Subset => %{
    0 => %{
      name => a
      text => Alpha
    }
    1 => %{
      name => b
      text => Beta
    }
  }

=cut

Testing hash of hashes

=test(match)

  # Get the value whose key is eq 'a'
  ttt_query('hash_of_hashes/{?:a}');

=result

  Data::OrderedHash => %{
    text => Alpha
    num => 3
  }

=test(match)

  # Get the value whose text is eq 'Alpha'
  ttt_query('hash_of_hashes/{?text:Alpha}');

=result

  Data::OrderedHash => %{
    text => Alpha
    num => 3
  }

=test(match)

  # Get all items whose text is eq 'Alpha'
  ttt_query('hash_of_hashes/{?text(eq):Alpha}');

=result

  Data::Hub::Subset => %{
    a => %{
      text => Alpha
      num => 3
    }
  }

=test(match)

  # Get all items whose num is > 1
  ttt_query('hash_of_hashes/{?num(>):1}');

=result

  Data::Hub::Subset => %{
    a => %{
      text => Alpha
      num => 3
    }
    b => %{
      text => Beta
      num => 2
    }
  }

=cut

Testing filters

=test(match)

  ttt_query('hash_of_hashes/*|{?(ne):b}');

=result

  Data::Hub::Subset => %{
    a => %{
      text => Alpha
      num => 3
    }
    c => %{
      text => Charlie
      num => 1
    }
  }

=test(match)

  ttt_query('hash_of_hashes/*|{?text(=~):B|C}');

=result

  Data::Hub::Subset => %{
    b => %{
      text => Beta
      num => 2
    }
    c => %{
      text => Charlie
      num => 1
    }
  }

=cut

=test(match)

  ttt_query('hash_of_hashes/*|{?(=~):[ab]}|{?text(=~):B|C}');

=result

  Data::Hub::Subset => %{
    b => %{
      text => Beta
      num => 2
    }
  }

=test(match)

  ttt_query('hash_of_hashes/{?(=~):[ab]}|{?text(=~):B|C}');

=result

  Data::Hub::Subset => %{
    b => %{
      text => Beta
      num => 2
    }
  }

=cut
