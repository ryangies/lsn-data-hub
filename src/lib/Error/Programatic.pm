package Error::Programatic;
use strict;
our $VERSION = 0;
use Perl::Options qw(my_opts);
use base qw(Error);

# ------------------------------------------------------------------------------
# new - Constructor
#
# We set Error::Depth to that which reflects the caller's perspective.
# ------------------------------------------------------------------------------
#|test(abort)
#|use Error::Programatic;
#|throw Error::NotStatic;
# ------------------------------------------------------------------------------

sub new {
  my $self = shift;
  my @stack = caller;
  my $opts = my_opts([@_]); # copy
  my $depth = $opts->{depth} || 0;
  $depth++ while (defined caller($depth));
  local $Error::Depth = $Error::Depth + ($depth > 2 ? 2 : 1);
  local $Error::Debug = 1; # Capture stacktrace
  @_ && $_[0] !~ /^-/ and unshift @_, '-text';
  $self->SUPER::new(@_);
}

sub throwf {
  my $self = shift;
  $self->SUPER::throw(sprintf(shift, @_));
}

sub ex_prefix {'Programatic error'}

sub stringify {
  my $self = shift;
  my $text = $self->message();
  $text .= sprintf(" at %s line %d.\n", $self->file, $self->line)
    unless($text =~ /\n$/s);
  $text;
}

sub message {
  my $self = shift;
  my $text = $self->ex_prefix;
  $self->{'-text'} and $text .= ': ' . $self->{'-text'};
  $text;
}

1;

package Error::NotStatic;
use base qw(Error::Programatic);
sub ex_prefix{'Static call to instance method'}
1;

package Error::IsStatic;
use base qw(Error::Programatic);
sub ex_prefix{'Static method called in instance context'}
1;

package Error::MissingArg;
use base qw(Error::Programatic);
sub ex_prefix{'Missing argument'}
1;

package Error::IllegalArg;
use base qw(Error::Programatic);
sub ex_prefix{'Illegal argument'}
1;
