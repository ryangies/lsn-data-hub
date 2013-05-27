package Parse::Padding;
use strict;
our $VERSION = 0;

use Perl::Module;
use Perl::Options qw(my_opts);
use Error::Programatic;

use base qw(Exporter);
our @EXPORT_OK = qw(padding trailing leading);
our %EXPORT_TAGS = (all=>[@EXPORT_OK]);

# ------------------------------------------------------------------------------
# padding - Get number of surrounding whitespace characters
# padding \$text, $begin_index, $end_index, [options]
#
# options:
#
#   -crlf       Just count surrounding cr/lf characters
#
# Returns an array of widths: ($w1, $w2)
#
#   $w1 = Number of preceeding whitespace characters
#   $w2 = Number of trailing whitespace characters
#
# Returns (0, 0) if non-whitespace characters are immediately found in the 
# preceeding or trailing regions.
#
# Returns C<undef> if C<$pos> is less than C<$[>
# ------------------------------------------------------------------------------
#|test(!abort) use Parse::Padding qw(padding);
# ------------------------------------------------------------------------------
#|test(match,4;3)
#|my $str = "    a   ";
#|join ';', padding(\$str, 4, 5);
# ------------------------------------------------------------------------------
#|test(match,2;3)
#|my $str = " \na\r\n ";
#|join ';', padding(\$str, 2, 3);
# ------------------------------------------------------------------------------
#|test(match,1;2)
#|my $str = " \na\r\n ";
#|join ';', padding(\$str, 2, 3, -crlf);
# ------------------------------------------------------------------------------
#|test(match,1;2)
#|my $str = " \n\na\r\n\r\n ";
#|join ';', padding(\$str, 3, 4, -crlf);
# ------------------------------------------------------------------------------
#|test(match,0;0)
#|my $str = " a ";
#|join ';', padding(\$str, 1, 2, -crlf);
# ------------------------------------------------------------------------------

sub padding {
  my $opts = my_opts(\@_);
  my ($text, $pos, $end_pos) = @_;
  return unless $pos >= $[;
  my ($prefix, $suffix) = (0,0);
  my $ws_regex = $opts->{crlf} ?  qr([\r\n]) : qr(\s);
  my $last_c = '';
  if ($pos > $[) {
    for (my $i = $pos - 1; $i >= $[; $i--) {
      my $prev_c = substr $$text, $i, 1;
      last unless $prev_c =~ $ws_regex;
      last if $opts->{crlf} && (($prev_c eq $last_c) || ($prefix >= 2));
      $last_c = $prev_c;
      $prefix++;
    }
  }
  $last_c = '';
  for my $i ($end_pos .. length($$text)) {
    my $next_c = substr $$text, $i, 1;
    last unless $next_c =~ $ws_regex;
    last if $opts->{crlf} && (($next_c eq $last_c) || ($suffix >= 2));
    $last_c = $next_c;
    $suffix++;
  }
  ($prefix, $suffix);
}

# ------------------------------------------------------------------------------
# trailing - Count trailing characters
# trailing $chars, \$text, $begin_index
#
# where:
#
#   $chars        # characters to count
#   \$text        # text to search
#   $begin_index  # index within $text to start searching
#   $eol          # if true, $chars must be at end-of-line
# ------------------------------------------------------------------------------
#|test(!abort) use Parse::Padding qw(trailing);
#|test(abort) trailing('\r\n', " xxx\r\n", 'abc'); # invalid index
#|test(abort) trailing('', " xxx\r\n", 4); # invalid chars
#|test(match,3) trailing('\s', " xxx \r\n", 4);
#|test(match,0) trailing('\r\n', " xxx \r\n", 4);
#|test(match,2) trailing('\r\n', " xxx\r\n", 4);
#|test(match,0) trailing('\r\n', " xxx\r\n", 999);
#|test(match,0) trailing('\r\n', " xxx\r\n", -999);
#|test(match,2) trailing('\r\n', "\r\n\r\n", 0, 1);
#|test(match,1) trailing('\r\n', "\n\n\n", 0, 1);
#|test(match,1) trailing('abcd', "a\na", 2, 1); # end-of-string == $eol
# ------------------------------------------------------------------------------

sub trailing {
  my ($chars, $text, $beg, $eol) = @_;
  my $str = ref($text) ? $text : \$text;
  throw Error::IllegalArg unless is_numeric($beg);
  my $pos = $beg;
  my $c = undef;
  my $rs = undef;
  my $len = length($$str);
  while ($pos >= 0 && $pos < $len) {
    $c = substr $$str, $pos, 1;
    last unless $c =~ /[$chars]/;
    if ($eol) {
      if ($rs) {
        $pos++ if (($c eq "\r" || $c eq "\n") && $c ne $rs);
        last;
      }
      $rs = $c if ($c eq "\r" || $c eq "\n");
    }
    $pos++;
  }
  if ($eol) {
    return 0 if $chars !~ /\\[rn]/ && $c !~ /[\r\n]/ && $pos != $len;
  }
  $pos - $beg;
}

# ------------------------------------------------------------------------------
# leading - Count leading characters
# leading $chars, \$text, $begin_index, $bol
#
# where:
#
#   $chars        # characters to count
#   \$text        # text to search
#   $begin_index  # index within $text to start searching
#   $bol          # if true, $chars must be at begin-of-line
# ------------------------------------------------------------------------------
#|test(!abort) use Parse::Padding qw(leading);
#|test(match,1) leading('\s', " xxx", 1);
#|test(match,3) leading('\s', "\r \nxxx", 3);
#|test(match,0) leading('\r\n', " xxx", 1);
#|test(match,3) leading('\r\n', "\r\n\rxxx", 3);
#|test(match,0) leading('\r\n', "\r\n\rxxx", -999);
#|test(match,0) leading('\r\n', "\r\n\rxxx", 999);
#|test(abort) leading('', "\r\n\rxxx", 3); # invalid chars
#|test(abort) leading('\r\n', "\r\n\rxxx", 'abc'); # invalid index
#|test(match,1) leading('abcd', "axe", 1, 1); # begin-of-string == $bol
#|test(match,1) leading('abcd', "\naxe", 2, 1);
# ------------------------------------------------------------------------------

sub leading {
  my ($chars, $text, $beg, $bol) = @_;
  my $str = ref($text) ? $text : \$text;
  throw Error::IllegalArg unless is_numeric($beg);
  my $pos = --$beg;
  my $c = undef;
  my $rs = undef;
  while ($pos >= 0 && $pos < length($$str)) {
    $c = substr $$str, $pos, 1;
    last unless $c =~ /[$chars]/;
    if ($bol) {
      if ($rs) {
        $pos-- if (($c eq "\r" || $c eq "\n") && $c ne $rs);
        last;
      }
      $rs = $c if $c eq "\r" || $c eq "\n";
    }
    $pos--;
  }
  if ($bol) {
    return 0 unless ($c =~ /[\r\n]/ || $pos == -1);
  }
  $beg - $pos;
}

1;
