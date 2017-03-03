package Data::Comparison;
use strict;
our $VERSION = 0.1;

use Exporter qw(import);
use Perl::Module;
use Error::Programatic;
use Data::Hub::Address;
use Data::Hub::Util qw(addr_parent addr_pop);

our @EXPORT = qw();
our @EXPORT_OK = qw(
  diff
  merge
);
our %EXPORT_TAGS = (all => [@EXPORT_OK],);

# ------------------------------------------------------------------------------
# diff - Recursively diff two similar structures, returning addr/val pairs
#   diff \%left, \%right
#   diff \@left, \@right
# Sample output:
#   [
#     ['+', 'a',   'Cartman'],          # Item a has been added and the value is 'Cartman'
#     ['-', 'b'],                       # Item b has been removed
#     ['>', 'c/1', 'Cartman'],          # The value of array c at index 1 is now 'Cartman'
#     ['#', 'e/g', ['a', 'b', 'c'],     # The order of keys in hash e/g changed to a, b, c
#   ]
# ------------------------------------------------------------------------------

sub diff {
  my ($left, $right) = @_;
  $left ||= {};
  $right ||= {};
  my $addr = Data::Hub::Address->new();
  my $result = Data::Comparison::Diff->new();
  _diff($addr, $left, $right, $result);
  $result;
}

sub _diff {
  my ($addr, $left, $right, $result) = @_;
  if (!defined($left) && !defined($right)) {
  } elsif (!defined($left) && defined($right)) {
    push @$result, ['+', $addr->to_string, $right];
  } elsif (defined($left) && !defined($right)) {
    push @$result, ['-', $addr->to_string];
  } elsif (reftype($left) ne reftype($right)) {
    push @$result, ['>', $addr->to_string, $right];
  } else {
    if (isa($left, 'HASH')) {
      my @keys1 = keys %$left;
      my @keys2 = keys %$right;
      my @key_order = @keys2;
      my $has_changed_order = 0;
      my $idx = 0;
      while (@keys2 || @keys1) {
        my $k1 = shift @keys1;
        my $k2 = shift @keys2;
        if (defined($k1) && defined($k2)) {
          if ($k1 eq $k2) {
            my $k = $k1;
            $addr->push($k);
            _diff($addr, $left->{$k}, $right->{$k}, $result);
            $addr->pop();
          } else {
            $has_changed_order ||= 1;
            my $k_idx = undef;
            $k_idx = grep_first_index(sub {$_ eq $k1}, @keys2);
            if (defined($k_idx)) {
              splice @keys2, $k_idx, 1;
              $addr->push($k1);
              _diff($addr, $left->{$k1}, $right->{$k1}, $result);
              $addr->pop();
            } else {
              push @$result, ['-', $addr->to_string($k1)];
            }
            $k_idx = grep_first_index(sub {$_ eq $k2}, @keys1);
            if (defined($k_idx)) {
              splice @keys1, $k_idx, 1;
              $addr->push($k2);
              _diff($addr, $left->{$k2}, $right->{$k2}, $result);
              $addr->pop();
            } else {
              push @$result, ['+', $addr->to_string($k2), $right->{$k2}];
            }
          }
        } elsif (defined($k1)) {
          push @$result, ['-', $addr->to_string($k1)];
        } elsif (defined($k2)) {
          push @$result, ['+', $addr->to_string($k2), $right->{$k2}];
        }
        $idx++;
      }
      if ($has_changed_order) {
        push @$result, ['#', $addr->to_string(), \@key_order];
      }
    } elsif (isa($left, 'ARRAY')) {
      my $len = @$left > @$right ? @$left : @$right;
      for (my $i = 0; $i < $len; $i++) {
        $addr->push($i);
        _diff($addr, $left->[$i], $right->[$i], $result);
        $addr->pop();
      }
    } elsif (isa($left, 'SCALAR')) {
      if ($$left ne $$right) {
        push @$result, ['>', $addr->to_string, $right];
      }
    } elsif (ref($left) eq 'REF') {
      if ($$left eq $left || $$right eq $right) {
        warn "Self reference cannot be dereferenced";
      } else {
        _diff($addr, $$left, $$right, $result);
      }
    } else {
      if ($left ne $right) {
        push @$result, ['>', $addr->to_string, $right];
      }
    }
  }
}

# ------------------------------------------------------------------------------
# merge - Update the target structure according to the diff
# merge $dest, $diff
#
# where
#
#   $dest is usually the $left passed to L<diff>
#   $diff is the result of L<diff>
#
# The special C<next> value
# 
#   If the new value is '<next>',
#   and the $dest value is numeric or not set,
#   then the new value becomes the old value + 1.
#
# This way a counter can be incremented even when another process incremented
# the same counter between the time our process read the file and writes it
# back out.
# ------------------------------------------------------------------------------

sub merge {
  my ($dest, $diff) = @_;
  throw Error::Programatic unless isa($diff, 'Data::Comparison::Diff');
  my %array_offsets = ();
  for (@$diff) {
    my ($opr, $addr, $val) = @$_;
    if ($opr eq '-') {
      my $paddr = addr_parent($addr);
      my $p = $paddr ? $dest->get($paddr) : $dest;
      if (isa($p, 'ARRAY')) {
        my $offset = $array_offsets{$paddr} || 0;
        my $idx = addr_pop($addr) - $offset;
        splice @$p, $idx, 1;
        $array_offsets{$paddr} = $offset + 1;
      } else {
        $dest->delete($addr);
      }
    } elsif ($opr eq '+' || $opr eq '>') {
      if ($val eq '<next>') {
        my $orig_val = $dest->get($addr) || 0;
        $val = $orig_val + 1 if is_numeric($orig_val);
      }
      $dest->set($addr, $val);
    } elsif ($opr eq '#') {
      my $h = $addr ? $dest->get($addr) : $dest;
      next unless can($h, 'sort_by_key');
      my $i = 0;
      my %order = ();
      for (@$val) {
        $order{$_} = $i++;
      }
      $h->sort_by_key(sub {
        $order{$_[0]} <=> $order{$_[1]};
      });
    } else {
      throw Error::Programatic 'Unknown diff operation';
    }
  }
}

1;

package Data::Comparison::Diff;
use Perl::Module;

sub new {
  my $classname = ref($_[0]) ? ref(shift) : shift;
  bless [], $classname;
}

sub to_string {
  my $self = shift;
  my $result = '';
  for (@$self) {
    my ($opr, $addr, $val) = @$_;
    $val = '' unless defined $val;
    $val = join(',', @$val) if isa($val, 'ARRAY');
    $result .= sprintf "%s %-20s %s\n", $opr, $addr, $val;
  }
  return $result;
}

1;
