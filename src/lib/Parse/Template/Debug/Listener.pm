package Parse::Template::Debug::Listener;
use strict;
sub new {
  my $class = shift;
  $class = ref($class) || $class;
  my $str = undef;
  my $self = bless \$str, (ref($class) || $class);
  tie $$self, $class, @_;
  $self;
}
sub TIESCALAR {my $class = shift; bless [@_], $class;}
sub DESTROY {}
sub FETCH {''}
sub STORE {my $o = shift; &{$o->[0]}(@_)}
1;
