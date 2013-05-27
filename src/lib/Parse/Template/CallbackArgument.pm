package Parse::Template::CallbackArgument;
use strict;
use Perl::Module;
use Error::Programatic;

sub new {
  my $classname = ref($_[0]) ? ref(shift) : shift;
  my $self = bless [@_], $classname;
  $self;
}

1;
