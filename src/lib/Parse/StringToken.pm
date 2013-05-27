package Parse::StringToken;
use strict;
our $VERSION = 1;

use Exporter;
use Perl::Module;
use Parse::StringTokenizer;
use Error::Programatic;

our @EXPORT_OK = qw(str_token);
our %EXPORT_TAGS = (all => [@EXPORT_OK],);
push our @ISA, qw(Exporter);

# Indexes into $self
use constant {
  STR => 0,
  TOKENIZER => 1,
};

# ------------------------------------------------------------------------------
#|test(!abort) use Parse::StringToken qw(:all); # Include symbols
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# str_token - Construct an instance of __PACKAGE__
# str_token @parameters
# If the first parameter is an instance of __PACKAGE__, it will be returned
# without modification.
# See also L</new>
# ------------------------------------------------------------------------------

sub str_token(@) { isa($_[0], __PACKAGE__) ? $_[0] : __PACKAGE__->new(@_); }

# ------------------------------------------------------------------------------
# new - Constructor
# new $string, [$separator], [options]
# new \$string, [$separator], [options]
#
# When $string is passed by reference, it will be modified by L<shift>, and 
# L<pop>.
# 
# See L<Parse::StringTokenizer> for options
# ------------------------------------------------------------------------------
#|test(abort) str_token('', -contained => '123'); # Needs to have matching pairs
# ------------------------------------------------------------------------------

sub new(@) {
  my $class = shift;
  my $str = shift;
  bless [ref($str) ? $str : \$str, Parse::StringTokenizer->new(@_)],
    (ref($class) || $class);
}

# ------------------------------------------------------------------------------
# shift - Return the next token and trim the string
# shift
# ------------------------------------------------------------------------------
#|test(match,a) str_token("a b c")->shift; # Basic
#|test(match) # Contains spaces
#|  my $s = str_token(q(one 'and a two' "and a three"));
#|  $s->shift; $s->shift;
#=and a two
# ------------------------------------------------------------------------------
# TODO
# ------------------------------------------------------------------------------
# test(match) # Contains escaped quotes
#   my $s = str_token(q(100.3 '7\' 12"' 1.325E+10));
#   $s->shift; $s->shift;
# \'7\\\' 12"\'
# ------------------------------------------------------------------------------

sub shift($) {
  my $self = CORE::shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  $$self[TOKENIZER]->shift($$self[STR]);
}

# ------------------------------------------------------------------------------
# pop - Return the last token and trim the string
# pop
# ------------------------------------------------------------------------------
#|test(match,c) str_token("a b c")->pop; # Basic
#|test(match) # Contains spaces
#|  my $s = str_token(q(one 'and a two' "and a three"));
#|  $s->pop;
#|  $s->pop;
#=and a two
# ------------------------------------------------------------------------------

sub pop($) {
  my $self = CORE::shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  $$self[TOKENIZER]->pop($$self[STR]);
}

# ------------------------------------------------------------------------------
# split - Get an array of all tokens
# split
# ------------------------------------------------------------------------------
#|test(match,a-b-c) join('-', str_token("a b c")->split); # Basic
# ------------------------------------------------------------------------------

sub split($) {
  my $self = CORE::shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  $$self[TOKENIZER]->split($$self[STR]);
}

1;

__END__

=pod:summary Object for tokenized strings

No symbols are exported by default.

=pod:synopsis

  use Perl::StringToken qw(str_token);
  die unless 'a' eq str_token("a b c")->shift;

=pod:description

See L<Parse::StringTokenizer>

=cut
