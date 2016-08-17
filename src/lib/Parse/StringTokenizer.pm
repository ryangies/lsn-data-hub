package Parse::StringTokenizer;
use strict;
our $VERSION = 1;

use Perl::Module;
use Error::Programatic;

# ------------------------------------------------------------------------------
# new - Constructor
# new [options]
#
# options:
#
#   -delim => $delimiter      # Token separator
#   -quotes => $quotes        # Quote characters which protect the
#                             # delimiter, and will be ignored
#   -contained => $chars      # Character pairs which protect the delimiter
#   -keywords => \@keywords   # Words which will not be split
#   -preserve => 1            # Preserve quotes which surround each field
#
# By default, the following is considered three tokens:
#
#   one 'and a two' "and a three"
#
# ------------------------------------------------------------------------------

sub new {
  my $class = ref($_[0]) ? ref(CORE::shift) : CORE::shift;
  my $opts = my_opts(\@_, {
    delim => q(\s),
    quotes => q('"),
    contained => q(),
    keywords => [],
  });
  my $self = bless {re => undef, opts => $opts}, $class;
  $self->_compile;
  $self;
}

# ------------------------------------------------------------------------------
# _compile - Compile the regular expression
#
# Quotes and contained segments can have escaped characters, like:
#
#   'don\'t break me'
#
# right now, it comes back as
#
#   dont\'t break me
#
# TODO, unescape it so it becomes
#
#   dont't break me
#
# the difficulty is that you DO NOT want to unescape the backslashes here
#
#   "my quotes \'are\' different"
#
# which means reworking the RE such that the leading and tailing quotes are 
# NOT removed, i.e., they remain part of the segment.  and a subsequent 
# step added to `unpack` which knows what to do by the presence of leading and
# trailing characters.
# ------------------------------------------------------------------------------

sub _compile {
  my $self = CORE::shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $opts = $self->{opts};

  # -contained specifies a string of characters which protect the delimiter.
  # They are first split into an array of pairs, i.e., "{}()" would become
  # ["{}", "()"].
  throw Error::Programatic "Provide matching pairs"
    unless (length($$opts{'contained'}) % 2) == 0;
  my @contained = $opts->{contained} =~ /(\\?.\\?.)/g;

  # -quotes specifies a string of identical characters which protect the
  # delimiter.  They are first split into an array, i.e., q("') would become
  # ['"', '\'']
  my @quotes = $opts->{quotes} =~ /(\\?.)/g;
  my $keywords = join('|', @{$opts->{keywords}});
  my $d = $opts->{delim};

  # @fields is the list of patterns which make up valid fields, that is the
  # stuff in between the delimeters.
  my @fields = ();

  # TODO Matching any char (.) fixes the problem where you cannot escape
  # quotes, however this will confuse the regex engine sometimes, giving
  # a memory corruption error.
  #
  # push @fields, map {"(?<!\\\\)${_}(.*?)(?<!\\\\)${_}"} @quotes;
  #"((?:[^$d$l]*(?<!\\\\)${l}.*?(?<!\\\\)${r}[^$d$l]*)+)"

  if ($opts->{'preserve'}) {
    push @fields, map {"(?<!\\\\)(${_}[^${_}]*(?<!\\\\)${_})"} @quotes;
  } else {
    push @fields, map {"(?<!\\\\)${_}([^${_}]*)(?<!\\\\)${_}"} @quotes;
  }
  push @fields, map {
    my ($l, $r) = $_ =~ /(\\?.)/g;
    "((?:[^$d$l]*(?<!\\\\)${l}[^${r}]*(?<!\\\\)${r}[^$d$l]*)+)"
  } @contained;
  push @fields, "([^$d]+)";
  my $fields = join('|', @fields);

  my @re = ();
  push @re, "(^)[$d]";
  push @re, "\\G[$d](\$)";
  push @re, "\\G[$d]($keywords)" if $keywords;
  push @re, "(\\G)[$d]{2}";
  push @re, "\\G[$d]?(?:$fields)";

  $self->{re} = sprintf qr/%s/, join('|', @re);

  $self->{primary_delim} = $d =~ /^\\/ ? q( ) : substr($d, 0, 1);
  $self->{primary_quote} = $quotes[0] && $quotes[0] =~ /^\\/ ? q(') : $quotes[0];
}

# ------------------------------------------------------------------------------
# split - Unpack the string and return non-empty fields
# split $str
# ------------------------------------------------------------------------------

sub split($) {
  my $self = CORE::shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  grep {defined($_) && $_ ne ''} $self->unpack(CORE::shift);
}

sub dbg_parse($) {
  my $self = CORE::shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $str = CORE::shift;
  return unless defined $str;
  isa($str, 'SCALAR') and $str = $$str;
  if (1) {
    my $copy = $str;
    my $strlen = length($str);
    while ($copy) {
      my $orig = $copy;
      my @match = $copy =~ /$self->{re}/;
      my @parts = grep defined $_, @match;
      $copy =~ s/$self->{re}//;
      my $delta = $strlen - length($orig);
      my $pad = ' ' x $delta;
      my $matched = join(' <!!!> ', @parts); # should always be 1
      warnf ">>> $pad(%s) : (%s)\n", $orig, $matched;
      last unless @match;
    }
  }
}

# ------------------------------------------------------------------------------
# unpack - Split a string into fields (opposite of pack)
# unpack $string
# ------------------------------------------------------------------------------

sub unpack($) {
  my $self = CORE::shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $str = CORE::shift;
  return unless defined $str;
  isa($str, 'SCALAR') and $str = $$str;
  my @parts = $str =~ /$self->{re}/g;
  grep(defined $_, @parts);
}

# ------------------------------------------------------------------------------
# pack - Join fields together as a string (opposite of unpack)
# pack @fields
#
# -preserve
#
#   TODO: when packing the field will be double quoted if it contains the
#   primary delimiter.  If the field is quoted, then do not double-quote
# ------------------------------------------------------------------------------

sub pack(@) {
  my $self = CORE::shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $d = $self->{primary_delim};
  my $q = $self->{primary_quote};
  my $str = join $d, map {$_ =~ /[$d]/ ? "$q$_$q" : $_} @_;
# my $str = join $d, map {defined($_) ? $_ : ''} @_;
  $str;
}

# ------------------------------------------------------------------------------
# shift - Return the first field and trim the string
# shift \$str
# ------------------------------------------------------------------------------

sub shift(\$$$) {
  my $self = CORE::shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $str = CORE::shift or return;
  confess
    unless isa($str, 'SCALAR');
  return $$str if (!defined $$str) || ($$str eq '');
  my @fields = $self->split($str);
  my $result = CORE::shift @fields;
  $$str = $self->pack(@fields);
  $result;
}

# ------------------------------------------------------------------------------
# pop - Return the last field and trim the string
# pop $str
# ------------------------------------------------------------------------------

sub pop(\$$) {
  my $self = CORE::shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $str = CORE::shift;
  confess
    unless isa($str, 'SCALAR');
  return unless defined $$str;
  my @fields = $self->unpack($str);
  my $result = CORE::pop @fields;
  $$str = $self->pack(@fields);
  $result;
}

# ------------------------------------------------------------------------------
# push - Push a field on to the string
# push $str
# Returns the new field count.
# ------------------------------------------------------------------------------

sub push(\$$) {
  my $self = CORE::shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $str = CORE::shift;
  confess
    unless isa($str, 'SCALAR');
  return unless defined $$str;
  my @fields = $self->unpack($str);
  my $result = CORE::push @fields, $_[0];
  $$str = $self->pack(@fields);
  $result;
}

1;

__END__

=pod:summary Extract fields from strings

No symbols are exported by default.

=pod:synopsis

  use Parse::StringTokenizer;
  my $tokenizer = String::Tokenizer->new();
  my $str = 'a b c';
  die unless 'a' eq $tokenizer->shift($str);
  die unless 'b c' eq $str;

=pod:description

Similiar in spirit to C<strtok>.

Default delimiter is whitespace (regex C<\s>).

Default quotes which protect the delimiter are: C<'">

=pod:todo

Implement these public methods:

  unshift - prepend a field and delimiter
  push    - append a delimiter and field

Maybe, allow a subroutine to manipulate each field...

  Parse::StringTokenizer->new('abraham lincoln')->iterate({
    ucfirst $_;
  });

=cut
