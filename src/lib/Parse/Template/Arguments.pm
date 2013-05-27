package Parse::Template::Arguments;
use strict;
use Perl::Module;
use Error::Programatic;
use Parse::Template::CallbackArgument;

sub new {
  my $classname = ref($_[0]) ? ref(shift) : shift;
  my $self = bless [], $classname;
  @_ and $self->parse(shift);
  $self;
}

# All '(' must have a closing ')'

sub parse ($) {
  my $self = shift;
  my $str = shift;
  ref($str) and throw Error::Programatic;
  my $parents = []; # pointers to arrays as we nest groups
  my $ptr = $self; # start at the top (note we do not clear ourselves)
  my $arg = undef; # the current argument to which characters are appended
  my $quoted = undef; # character which begins a quoted section
  my $depth = 0; # nested group depth
  my $slurp = 0; # slurping is on
  my $curly = 0; # scope is within curlys by matching '{' with '}'
  my @chars = split //, $str;
  while (@chars) {
    my $chr = shift @chars;
    if ($chr eq '\\') {
      # Literal character follows, eat the escape character
      $chr .= shift @chars;
    } elsif ($chr eq ')') {
      # Close the currently open group
      if ($depth-- == @$parents) { # track closes
        defined $arg and push @$ptr, $$arg;
        undef $arg;
        $ptr = pop @$parents;
        next;
      } else {
        $slurp--;
      }
    } elsif ($chr eq '(') {
      $depth++; # track opens
      my $group = undef;
      if (defined $arg && !$curly && !$quoted) {
        # callback argument
        $group = Parse::Template::CallbackArgument->new($$arg);
        undef $arg;
      } elsif (!defined($arg)) { # begins a segment
        # open a group, must be the beginning of a segment
        $group = [];
      }
      if ($group) {
        push @$ptr, $group;
        push @$parents, $ptr;
        $ptr = $group;
        next;
      } else {
        $slurp++;
      }
    } elsif ($slurp) {
      # continue to append character
    } elsif (!$quoted && ($chr eq ' ' || $chr eq ',' || $chr eq "\r" || $chr eq "\n")) {
      defined $arg and push @$ptr, $$arg;
      undef $arg;
      next;
    } elsif (!$quoted && ($chr eq '=')) {
      # assignment is the same as a separator, however must not be a logical 
      # operator '==|=~'
      if ((!defined($arg) || ($$arg ne '!' && $$arg ne '<' && $$arg ne '>' && $$arg ne '='))
          && $chars[0] ne '='
          && $chars[0] ne '~') {
        defined $arg and push @$ptr, $$arg;
        undef $arg;
        $chars[0] eq '>' and shift @chars; # => is treated as =
        next;
      }
    } elsif (!$quoted && $chr eq '!' && !defined($arg) && $chars[0] ne '=' && $chars[0] ne '~') {
      # unary not operator
      push @$ptr, $chr;
      next;
    } elsif (!$quoted && $chr eq '{') {
      $curly++;
    } elsif (!$quoted && $chr eq '}') {
      $curly--;
    } elsif ($chr eq '"' || $chr eq '\'' || $chr eq '`') {
      # quotes must begin a segment
      if ($quoted) {
        undef $quoted if $quoted eq $chr;
      } else {
        !defined $arg and $quoted = $chr;
      }
    }
    !defined $arg and $arg = str_ref(); # bareword begins a segment
    $$arg .= $chr; # append current character
  }
  defined $arg and push @$ptr, $$arg;
  return $self;
}

sub clear {
  my $self = shift;
  @$self = ();
}

1;
