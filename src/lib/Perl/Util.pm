package Perl::Util;
use strict;
our $VERSION = 0;

use Exporter;
use Carp qw(croak);
use Error::Simple;
use Error::Programatic;
use Error::Logical;
#use POSIX;
use Compress::Zlib qw(crc32);
use Perl::Options qw(my_opts);
use Time::Piece;
use MIME::Base64;
use Scalar::Util qw(blessed);

our @EXPORT = qw();
our @EXPORT_CONST = qw(
  ONE_KB
  ONE_MB
  ONE_GB
  ONE_TB
  ONE_PB
  ONE_EB
  ONE_ZB
  ONE_YB
  EXPR_NUMERIC
);
our @EXPORT_STD = qw(
  warnf
  is_numeric
  int_div
  str_ref
  grep_first
  grep_first_index
  push_uniq
  unshift_uniq
  index_unescaped
  index_match
  index_imatch
  checksum
  bytesize
  reftype
  isa
  can
  strftime
  strptime
);
our @EXPORT_OK = (@EXPORT_CONST, @EXPORT_STD);
our %EXPORT_TAGS = (
  const => [@EXPORT_CONST],
  std => [@EXPORT_STD],
  all => [@EXPORT_OK],
);
push our @ISA, qw(Exporter);

# ------------------------------------------------------------------------------
#|test(!abort) use Perl::Util qw(:all); # Load this module
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# :const - Byte size constants
#
#   ONE_KB # kilo/kibi
#   ONE_MB # mega/mebi
#   ONE_GB # giga/gibi
#   ONE_TB # tera/tebi
#   ONE_PB # peta/pebi
#   ONE_EB # exa/exbi
#   ONE_ZB # zetta/zebi
#   ONE_YB # yotta/yobi
#
# See also: L</bytesize>, L<http://en.wikipedia.org/wiki/Byte>
# ------------------------------------------------------------------------------

use constant {
  ONE_KB => 2 ** 10, # kilo/kibi
  ONE_MB => 2 ** 20, # mega/mebi
  ONE_GB => 2 ** 30, # giga/gibi
  ONE_TB => 2 ** 40, # tera/tebi
  ONE_PB => 2 ** 50, # peta/pebi
  ONE_EB => 2 ** 60, # exa/exbi
  ONE_ZB => 2 ** 70, # zetta/zebi
  ONE_YB => 2 ** 80, # yotta/yobi
};

sub EXPR_NUMERIC() {'\A[+-]?(\.\d+|\d+|\d+\.\d+)([Ee][+-]?\d+)?\Z'}

# ------------------------------------------------------------------------------
# str_ref - Create a scalar reference
# ------------------------------------------------------------------------------
#|test(match,a) my $a = str_ref("a"); $$a;
# ------------------------------------------------------------------------------

sub str_ref {
  my $str = shift;
  if (defined($str)) {
    my $ref = ref($str);
    return if $ref && $ref ne 'SCALAR';
  } else {
    $str = '';
  }
  ref($str) ? $str : \$str;
}

# ------------------------------------------------------------------------------
# warnf - Akin to printf
# warnf $format, @values
# See also: C<sprintf>
# ------------------------------------------------------------------------------

sub warnf(@) {
  my $message = sprintf(shift, @_);
  if ($message !~ /\n$/) {
    my %call_info; 
    @call_info{qw(pack file line)} = caller();
    $message .= " at $call_info{file} line $call_info{line}\n";
  }
  warn $message;
}

# ------------------------------------------------------------------------------
# is_numeric - Is the given string a numeric
# is_numeric $str
# We use a (slower) regular expression technique because performing an eval 
# introduces inconspicuous security considerations.
# ------------------------------------------------------------------------------
#|test(true)  is_numeric('-1');
#|test(true)  is_numeric('0');
#|test(true)  is_numeric('+1');
#|test(true)  is_numeric('3.14');
#|test(true)  is_numeric('6.02214E23');
#|test(true)  is_numeric('6.626068e-34');
#|test(false) is_numeric('3.1.4');
#|test(false) is_numeric('');
#|test(false) is_numeric('three');
#|test(false) is_numeric(undef);
# ------------------------------------------------------------------------------

sub is_numeric($) {
  return unless defined $_[0];
  $_[0] =~ EXPR_NUMERIC;
}

# ------------------------------------------------------------------------------
# int_div - Integer division
# int_div $dividend, $divisor
# Returns an array with the number of times the divisor is contained in the
# dividend, and the remainder.
# ------------------------------------------------------------------------------
#|test(match,1r1) join('r',int_div(3,2)); # 3 divided by 2
#|test(match,1r1) join('r',int_div(3.9,2)); # 3.9 divided by 2 (does not round)
#|test(abort) int_div(3,0); # divide by zero
#|test(abort) int_div('three',1); # not numeric
# ------------------------------------------------------------------------------

sub int_div {
  throw Error::IllegalArg unless is_numeric($_[0]) && is_numeric($_[1]);
  throw Error::Logical 'Divide by zero' if $_[1] == 0;
  (int($_[0] / $_[1]), ($_[0] % $_[1]));
}

# ------------------------------------------------------------------------------
# grep_first - Like grep, but stop processing after the first true value
# grep_first &block @list
# ------------------------------------------------------------------------------
#|test(match) # first item with an 'a' in it
#|grep_first {/a/} qw(apple banana cherry);
#=apple
# ------------------------------------------------------------------------------

sub grep_first (&@) {
  my $block = shift;
# local $_; (removing as is causing segfault in perl > 5.8)
  foreach $_ (@_) {
    return $_ if &$block;
  }
  return undef;
}

# ------------------------------------------------------------------------------
# grep_first_index - Like grep_first, but return the index
# grep_first_index &block @list
# ------------------------------------------------------------------------------
#|test(match) # index of first item with an 'a' in it
#|grep_first_index {/a/} qw(apple banana cherry);
#=0
# ------------------------------------------------------------------------------

sub grep_first_index (&@) {
  my $block = shift;
  my $i = 0;
# local $_; (removing as is causing segfault in perl > 5.8)
  foreach $_ (@_) {
    return $i if &$block;
    $i++;
  }
  return undef;
}

# ------------------------------------------------------------------------------
# push_uniq - Push a value (or values) unless they exist
# push_uniq \@array, @values
# ------------------------------------------------------------------------------

sub push_uniq {
  my $a = shift;
  foreach my $item (@_) {
    push (@$a, $item) unless grep_first(sub { $_ eq $item }, @$a);
  }
}

# ------------------------------------------------------------------------------
# unshift_uniq - Unshift a value (or values) unless they exist
# unshift_uniq \@array, @values
# ------------------------------------------------------------------------------

sub unshift_uniq {
  my $a = shift;
  foreach my $item (reverse @_) {
    unshift (@$a, $item) unless grep_first(sub { $_ eq $item }, @$a);
  }
}

# ------------------------------------------------------------------------------
# index_unescaped - Locate unescaped character in string
# index_unescaped $string, $char
# index_unescaped $string, $char, $offset
# See also: C<index>
# ------------------------------------------------------------------------------

sub index_unescaped {
  my $p = index $_[0], $_[1], ($_[2] || 0);
  return $p if $p <= $[;
  substr($_[0], $p-1, 1) eq '\\'
    ? index_unescaped($_[0], $_[1], ($_[2]+$p+length($p)))
    : $p;
}

# ------------------------------------------------------------------------------
# index_match - Index of expression within a string
# index_match $string, $expression, $position
# index_match $string, $expression
#
# Index is -1 I<One less than the base C<$[>> when C<$expression> is not found.
#
# In array context, C<($index, $match)> is returned, where:
#
#   $index        Index of expression
#   $match        Matched substring
# ------------------------------------------------------------------------------
#|test(match,4)   index_match("abracadabra", "[cd]")
#|test(match,3)   index_match("abracadabra", "a", 3)
#|test(match,-1)  index_match("abracadabra", "d{2,2}")
#|test(match,4)   my ($p, $str) = index_match("scant", "can");
#|                $p + length($str);
#|test(match,7)   index_match("foobar foo bar", '\bfoo\b') # zero-width test
#|test(match,-1)  index_match("foobar foo bar", 'Bar') # no-match
#|test(match,0)   index_match("aa", "a")
#|test(match,1)   index_match("aa", "a", 1)
# ------------------------------------------------------------------------------

sub index_match { _index_match($_[0], $_[1], $_[2], 0); }

# ------------------------------------------------------------------------------
# index_imatch - Index of expression within a string (case insensitive)
# index_imatch $string, $expression, $position
# index_imatch $string, $expression
# See L</index_match>
# ------------------------------------------------------------------------------
#|test(match,3)  index_imatch("foobar foo bar", 'Bar') # Case insensitive match
#|test(match,2)  index_imatch(" b\n a", '\s*a') # Case insensitive match
# ------------------------------------------------------------------------------

sub index_imatch { _index_match($_[0], $_[1], $_[2], 1); }

# ------------------------------------------------------------------------------
# _index_match - Common implementation for L</index_match> and L</index_imatch>
# _index_match \$str, $re, $pos, $ic
# _index_match $str, $re, $pos, $ic
# where:
#   $str, \$str   Search string
#   $re           Substring expression
#   $pos          Start position (use undef, not zero unless you mean it)
#   $ic           Ignore case (boolean)
# ------------------------------------------------------------------------------

sub _index_match {
  my $str = ref($_[0]) ? $_[0] : \$_[0];
  pos($$str) = $_[2];
  $_[3] ? $$str =~ m!($_[1])!ig : $$str =~ m!($_[1])!g;
  !defined $` and return wantarray ? ($[-1, '') : $[-1;
  my $index = length($`);
  wantarray ? ($index, $1) : $index;
}

# ------------------------------------------------------------------------------
# checksum - Compute a checksum
# checksum @strings
# Parameters are utf8 encoded to avoid wide character issues.
# ------------------------------------------------------------------------------
#|test(match,1625030915) checksum('“Hello”', 'world');
# ------------------------------------------------------------------------------

sub checksum {
  my $buf = '';
  $buf .= $_ for grep {defined $_} @_;
  utf8::encode($buf);
  crc32($buf);
}

# ------------------------------------------------------------------------------
# bytesize - Convert bytes to human-readable byte size
# bytesize $bytes, [options]
#
# options:
#
#   -precision => 3     Use Three decimal places.
#   -binary_symbol      Use binary symbol (KiB instead of KB)
# ------------------------------------------------------------------------------
#|test(match,10 B) bytesize(10)
#|test(match,10.77 KB) bytesize(11028)
#|test(match,953.6743 MB) bytesize(1000 ** 3, -precision => 4)
#|test(match,1 GB) bytesize(2 ** 30)
#|test(match,512 PiB) bytesize(2 ** 59, -binary_symbol)
# ------------------------------------------------------------------------------

sub bytesize {
  my ($opts, $b) = my_opts(\@_, {
    precision => 2,
    binary_symbol => 0,
    units => 'B',
  });
  $b ||= 0;
  my ($num, $symbol)
    = $b < ONE_KB ? ($b, '')
    : $b < ONE_MB ? ($b/ONE_KB, 'K')
    : $b < ONE_GB ? ($b/ONE_MB, 'M')
    : $b < ONE_TB ? ($b/ONE_GB, 'G')
    : $b < ONE_PB ? ($b/ONE_TB, 'T')
    : $b < ONE_EB ? ($b/ONE_PB, 'P')
    : $b < ONE_ZB ? ($b/ONE_EB, 'E')
    : $b < ONE_YB ? ($b/ONE_ZB, 'Z')
    : ($b/ONE_YB, 'YB');
  $symbol .= 'i' if ($$opts{'binary_symbol'});
  $num = sprintf "%.$$opts{'precision'}f", $num;
  return sprintf("%.10g %s%s", $num, $symbol, $$opts{'units'});
}

# ------------------------------------------------------------------------------
# reftype - Extends Scalar::Util::reftype
# reftype $unk
#
# We differentiate between C<undef> and scalar input by only returning C<undef>
# when the unknown is undefined.
# ------------------------------------------------------------------------------
#|test(!defined)      reftype(undef)
#|test(match,)        reftype('')
#|test(match,HASH)    reftype({})
#|test(match,ARRAY)   reftype([])
#|test(match,SCALAR)  my $a = ''; reftype(\$a)
#|test(match,REF)     my $a = ''; my $b = \$a; reftype(\$b)
# ------------------------------------------------------------------------------

sub reftype {
  my $reftype = Scalar::Util::reftype($_[0]);
  return !defined($reftype) && defined($_[0]) ? '' : $reftype;
}

# ------------------------------------------------------------------------------
# isa - Static method which provides UNIVERSAL->isa functionality
# isa $obj, $type
# ------------------------------------------------------------------------------
#|test(true)          isa({}, 'HASH')
#|test(true)          isa([], 'ARRAY')
# ------------------------------------------------------------------------------

sub isa {
  return unless defined $_[0];
  return unless defined $_[1];
  return UNIVERSAL::isa(@_);
# TODO This is what we want, however causes deep recursion when $_[0] is really $self
# return blessed($_[0]) ? $_[0]->isa($_[1]) : reftype($_[0]) eq $_[1];
}

# ------------------------------------------------------------------------------
# can - Static method which provides UNIVERSAL->can functionality
# can $obj, $method
# ------------------------------------------------------------------------------

sub can {
  return unless defined $_[0];
  return unless defined $_[1];
  return UNIVERSAL::can(@_);
# TODO This is what we want, however causes deep recursion when $_[0] is really $self
# return blessed($_[0]) && $_[0]->can($_[1]);
}

# ------------------------------------------------------------------------------
# Time
# ------------------------------------------------------------------------------

use Time::Regex qw(:formats);
use Time::Regex::Strftime;
use Time::Regex::Strptime;
use DateTime;
use DateTime::TimeZone;
our $Strftime = Time::Regex::Strftime->new();
our $Strptime = Time::Regex::Strptime->new();

# %Time_Formats - Alias and values in strftime format.
#
# These values will be used by Time::Piece to both parse (strptime) and format
# (strftime) a given time.

our %Time_Formats = (

  seconds   => '%s',                               # Seconds since the epoch

  # I18N::Langinfo
  d_fmt     => $$Strftime{'d_fmt'},                # %x
  t_fmt     => $$Strftime{'t_fmt'},                # %X
  d_t_fmt   => $$Strftime{'d_t_fmt'},              # %c
  lc_time   => $$Strftime{'lc_time'},              # %+
  d_us_fmt  => $$Strftime{'d_us_fmt'},             # %D

  # Not sure what to name these
  _TODO_    => '%Y-%m-%d',                         # %F
  _TODO_    => '%a %b %d %H:%M:%S %Z %Y',          # Thu Mar 15 11:54:13 EDT 2012
  _TODO_    => '%a %b %d %H:%M:%S %Y',             # Thu Mar 15 11:54:13 2012

  # More common names
  utc       => FMT_UTC,
  gmt       => FMT_GMT,
  rfc822    => FMT_RFC822,
  rfc3339   => FMT_RFC3339,

);

# strftime
# strftime 'alias'
# strftime '%Y-%m-%d'
# strftime -localtime
# strftime -time => 'Sun, 30 Dec 1973 00:00:00 -0400'
# strftime -time => '1973-12-30' -time_format => '%Y-%m-%d'
# 
# Notes:
#
#   -time
#           When passing in time as seconds (%s), they must be
#           UTC seconds. This is because Time::Piece::strptime interprets
#           them this way, and it is the right thing to do if you're
#           in the business of using seconds.
#   
sub strftime {
  my $opts = my_opts(\@_);
  my $format = FMT_RFC822;
  if (my $spec = shift) {
    $format = $Time_Formats{$spec} || $spec;
  }
  my $time;
  if (my $val_time = $$opts{'time'}) {
    my $fmt_time = $$opts{'time_format'} || $$opts{'time-format'}
        || $Strptime->compare($val_time, values %Time_Formats);
    if ($fmt_time) {
#     warn "Reading time '$val_time' using format: $fmt_time\n";
      $time = Time::Piece->strptime($val_time, $fmt_time);
      if ($$opts{'localtime'} || ($fmt_time eq $Time_Formats{'seconds'})) {
        my $tz = DateTime::TimeZone->new(name => 'local');
        my $dt = DateTime->new(
          year       => $time->year,
          month      => $time->mon,
          day        => $time->day_of_month,
          hour       => $time->hour,
          minute     => $time->min,
          second     => $time->sec,
          nanosecond => 0,
          time_zone  => 'GMT',
        );
        my $offset = $tz->offset_for_datetime($dt);
        $time += $offset if $fmt_time eq $Time_Formats{'seconds'};
        $time += $offset if $$opts{'localtime'};
      }
    } else {
      warn "Cannot detect time format: $val_time";
      return $val_time;
    }
  } else {
    my $t = Time::Piece->new; # Current time
    $time = $$opts{'localtime'} ? $t->localtime : $t->gmtime
  }
  unless ($$opts{'localtime'}) {
    $format =~ s/\%[zZ]\b/UTC/;
  }
  return $time->strftime($format);
}

# strptime 'Sun, 30 Dec 1973 00:00:00 -0400'
# strptime 'Sun, 30 Dec 1973 00:00:00 -0400' -localtime
# strptime '1973-12-30' -time_format => '%Y-%m-%d'
sub strptime {
  my $opts = my_opts(\@_);
  my $time = undef;
  my $val_time = shift || 0;
  my $fmt_time = $$opts{'time_format'} || $$opts{'time-format'}
      || $Strptime->compare($val_time, values %Time_Formats);
  if ($fmt_time) {
    $time = Time::Piece->strptime($val_time, $fmt_time);
    if ($$opts{'localtime'}) {
      my $tz = DateTime::TimeZone->new(name => 'local');
      my $dt = DateTime->new(
        year       => $time->year,
        month      => $time->mon,
        day        => $time->day_of_month,
        hour       => $time->hour,
        minute     => $time->min,
        second     => $time->sec,
        nanosecond => 0,
        time_zone  => 'GMT',
      );
      my $offset = $tz->offset_for_datetime($dt);
      $time += $offset;
    }
  } else {
    warn "Cannot detect time format: $val_time";
    return $val_time;
  }
  return $time;
}

1;

__END__

=pod:summary Perl Extensions

=pod:synopsis

  use Perl::Util qw(grep_first);
  grep_first {$_ eq 'b'} qw(a b b c);

=pod:description

=cut
