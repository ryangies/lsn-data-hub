package Perl::Compare;
use strict;
use Exporter;
our $VERSION = 0.1;
our @EXPORT_OK = qw(compare sort_compare sort_keydepth);
our %EXPORT_TAGS = ('all' => [@EXPORT_OK]);
push our @ISA, qw(Exporter);

# ------------------------------------------------------------------------------
# %COMPARISIONS - Comparison routines
# ------------------------------------------------------------------------------
# The key is the comparison operator. The value is the subroutine which is 
# executed.
#
# If you wanted to define an operator named C<opr>, you would:
#
#   Perl::Compare::COMPARISONS{'opr'} = sub {
#     # your code here
#   };
#
# Your comparison is invoked by:
#
#   compare('opr', 'a', 'b');
#
# And your subroutine will be passed C<'a'> and C<'b'>.  In fact, all arguments
# are passed, allowing you to write tertiary comparisons, such as:
#
#   compare('opr', 'a', 'b', 'c');
# ------------------------------------------------------------------------------

our %COMPARISONS = (

  # The sequence !0 is used for returning true.

  '&&'        => sub { $_[0] && $_[1]; },
  '||'        => sub { $_[0] || $_[1]; },

  'eq'        => sub { _either_undef(@_) ? undef : $_[0] eq $_[1]; },
  'ne'        => sub { _either_undef(@_) ? !0    : $_[0] ne $_[1]; },
  'lt'        => sub { _either_undef(@_) ? undef : $_[0] lt $_[1]; },
  'le'        => sub { _either_undef(@_) ? undef : $_[0] le $_[1]; },
  'gt'        => sub { _either_undef(@_) ? undef : $_[0] gt $_[1]; },
  'ge'        => sub { _either_undef(@_) ? undef : $_[0] ge $_[1]; },

  '=~'        => sub { _either_undef(@_) ? undef : $_[0] =~ $_[1]; },
  '!~'        => sub { _either_undef(@_) ? !0    : $_[0] !~ $_[1]; },

  '=='        => sub { _both_undef(@_) ? !0 : _either_undef(@_) ? !1 : $_[0] == $_[1]; },
  '!='        => sub { _either_undef(@_) ? !0    : $_[0] != $_[1]; },
  '<'         => sub { _either_undef(@_) ? undef : $_[0] <  $_[1]; },
  '>'         => sub { _either_undef(@_) ? undef : $_[0] >  $_[1]; },
  '<='        => sub { _either_undef(@_) ? undef : $_[0] <= $_[1]; },
  '>='        => sub { _either_undef(@_) ? undef : $_[0] >= $_[1]; },

  '<=>'       => sub { no warnings 'uninitialized'; $_[0] <=> $_[1]; },
  'cmp'       => sub { no warnings 'uninitialized'; $_[0] cmp $_[1]; },
  'leg'       => sub { no warnings 'uninitialized'; $_[0] cmp $_[1]; },

  # Extensions (above and beyond perl operators)

  '=~i'       => sub { _either_undef(@_) ? undef : $_[0] =~ /$_[1]/i; },
  '!~i'       => sub { _either_undef(@_) ? !0    : $_[0] !~ /$_[1]/i; },
  'eqic'      => sub { _either_undef(@_) ? undef : lc($_[0]) eq lc($_[1]); },
  'neic'      => sub { _either_undef(@_) ? !0    : lc($_[0]) ne lc($_[1]); },
  'mod'       => sub { _either_undef(@_) ? undef : ($_[0] >= $_[1]) && ($_[0] % $_[1] == 0); },
  'bw'        => sub { _either_undef(@_) ? undef : index($_[0], $_[1]) == 0 },
  'ew'        => sub { _either_undef(@_) ? undef : substr($_[0], $[ - length($_[1])) eq $_[1]; },

);

# ------------------------------------------------------------------------------
# _either_undef - Are either operands undefined?
# _either_undef $a, $b
# ------------------------------------------------------------------------------

sub _either_undef {
  !defined($_[0]) || !defined($_[1]);
}

# ------------------------------------------------------------------------------
# _both_undef - Are both operands undefined?
# _both_undef $a, $b
# ------------------------------------------------------------------------------

sub _both_undef {
  !defined($_[0]) && !defined($_[1]);
}

# ------------------------------------------------------------------------------
# compare - Wrapper for Perl's internal comparison operators.
# compare $comparator, $a, $b
#
# Support runtime comparison when the operator is held as a scalar.
#
# Where C<$comparator> may be one of:
#
#   &&        $a and $b are true vlaues
#   ||        $a or $b is a true value
#   eq        Stringwise equal
#   ne        Stringwise not equal
#   lt        Stringwise less than
#   le        Stringwise less than or equal
#   gt        Stringwise greater than
#   ge        Stringwise greater than or equal
#   =~        Regular expression match
#   !~        Regular expression does not match
#   cmp       Stringwise less-than, equal-to, or greater-than
#   leg       Alias for cmp (see Perl 6)
#   ==        Numeric equal
#   !=        Numeric not equal
#   <         Numeric less than
#   >         Numeric greater than
#   <=        Numeric less than or equal
#   >=        Numeric greater than or equal
#   <=>       Numeric less-than, equal-to, or greater-than
#
#   =~i       Regular expression match, case insensitive
#   !~i       Regular expression does not match, case insensitive
#   eqic      Equal ignoring case
#   neic      Not equal ignoring case
#   mod       Modulo
#   bw        Stringwise begins-with
#   ew        Stringwise ends-with
# ------------------------------------------------------------------------------
#|test(false)   compare('eq','',undef);
#|test(true)    compare('eq','abc','abc');
#|test(true)    compare('ne','abc','Abc');
#|test(false)   compare('eq','abc',undef);
#|test(true)    compare('!~','abc','A');
#|test(true)    compare('=~','abc','a');
#|test(true)    compare('==',1234,1234);
#|test(true)    compare('>=',1234,1234);
#|test(true)    compare('eqic','abc','Abc');
#|test(true)    compare('==',undef,undef);
#|test(false)   compare('==',0,undef);
#|test(false)   compare('!~i','abc','A');
#|test(true)    compare('=~i','abc','A');
#|test(true)    compare('eqic','abc','Abc');
#|test(false)   compare('neic','abc','Abc');
#|test(true)    compare('mod',4,2);
#|test(true)    compare('bw','abc','a');
#|test(false)   compare('bw','abc','b');
#|test(false)   compare('ew','abc','b');
#|test(true)    compare('ew','abc','c');
# ------------------------------------------------------------------------------

sub compare {
  my $comparator = shift or die 'Comparator required';
  die "Unknown comparator: $comparator" unless defined $COMPARISONS{$comparator};
  &{$COMPARISONS{$comparator}};
}

# ------------------------------------------------------------------------------
# sort_compare - Compare for sorting, returning 1, 0 or -1
# sort_compare $comparator, $a, $b
# See also L</compare>
# ------------------------------------------------------------------------------
#|test(match)   my @numbers = ( 20, 1, 10, 2 );
#|              join ';', sort { &sort_compare('<=>',$a,$b) } @numbers;
#~              1;2;10;20
# ------------------------------------------------------------------------------

sub sort_compare {
  my $comparator = shift or die 'Comparator required';
  die "Unknown comparator: $comparator" unless defined $COMPARISONS{$comparator};
  return defined $_[0]
    ? defined $_[1]
      ? &{$COMPARISONS{$comparator}}
      : 1
    : defined $_[1]
      ? -1
      : 0;
}

# ------------------------------------------------------------------------------
# sort_keydepth - Sort by the number of nodes in the key
# sort_keydepth $a, $b
# The key is the solodus (/) character.
# ------------------------------------------------------------------------------
#|test(!abort) use Perl::Compare qw(sort_keydepth);
#
#|test(match) # The deepest elements come last
#|join ';', sort {&sort_keydepth($a, $b)} qw(t/w/o o/ne th/r/e/e);
#=o/ne;t/w/o;th/r/e/e
#
#|test(match) # Those without come after undefined but before those with
#|no warnings 'uninitialized';
#|join ';', sort {&sort_keydepth($a, $b)} (qw(t/w/o o/ne none th/r/e/e), undef);
#=;none;o/ne;t/w/o;th/r/e/e
# ------------------------------------------------------------------------------

sub sort_keydepth {
  (defined $_[0] ? $_[0] =~ tr'/'' : -1)
    <=>
  (defined $_[1] ? $_[1] =~ tr'/'' : -1)
}

1;

__END__

=pod:summary Runtime access to perl comparison operators

=pod:synopsis

  use Perl::Compare qw(compare);
  print compare('eq', 'abc', 'xyz') ? "True\n" : "False\n";

  use Perl::Compare qw(sort_compare);
  my @items = qw(The black cat climbed the green tree);
  sort { &sort_compare('cmp', $a, $b) } @items;

=pod:description

Efficient routine to compare scalar values when the operator is variable.  This 
is particularly useful for dynamic patterns, such as those read in from a 
configuration file, taken from an argument, or specified in a table somewhere.

=head2 Motivation

Efficiency and security, invoking eval (as C<eval> or C<m//e>) is not an 
option.

In some situations, the logic is more important than the function.  Just like
when you would use C<no warnings>.  For this reason these routines simply 
return the logical answer when values are undefined.

Basic functionality which can be extended.  Okay, it's just nice to have some 
sugar some times.  Extending this package with your own comparison routines 
should be straight foward.  A few that we have added are:

  mod       Modulo
  bw        Stringwise begins-with
  ew        Stringwise ends-with

=head2 Notes

Because one cannot pass modifiers to the regular expression engine, the 
following extensions were added:

  =~i       Regular expression match, case insensitive
  !~i       Regular expression does not match, case insensitive
  eqic      Equal ignoring case
  neic      Not equal ignoring case

=cut
