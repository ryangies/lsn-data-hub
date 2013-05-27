package Perl::Class;
use strict;
our %NAMESPACE = ();
sub new {
  my $class = ref($_[0]) ? ref(shift) : shift;
  my $self = bless shift, $class;
  $self->__init(@_);
}
sub __init {
  my $self = shift;
  my $vars = $NAMESPACE{$self} ||= {};
  {
    no warnings qw(misc);
    %$vars = @_;
  }
  $self;
}
sub __ {$NAMESPACE{scalar($_[0])}}
sub DESTROY {
  delete $NAMESPACE{scalar($_[0])};
}
1;

package Perl::Class::Hash;
use base qw(Perl::Class);
sub new {
  my $class = ref($_[0]) ? ref(shift) : shift;
  my $self = bless {}, $class;
  $self->__init(@_);
}
1;

package Perl::Class::OrderedHash;
use Data::OrderedHash;
use base qw(Perl::Class);
sub new {
  my $class = ref($_[0]) ? ref(shift) : shift;
  my $self = bless Data::OrderedHash->new, $class;
  $self->__init(@_);
}
1;

package Perl::Class::Array;
use base qw(Perl::Class);
sub new {
  my $class = ref($_[0]) ? ref(shift) : shift;
  my $self = bless [], $class;
  $self->__init(@_);
}
1;

package Perl::Class::Scalar;
use base qw(Perl::Class);
sub new {
  my $class = ref($_[0]) ? ref(shift) : shift;
  my $null = undef;
  my $self = bless \$null, $class;
  $self->__init(@_);
}
1;

__END__

=test(match,3:|:1:odd)

  package Foo;
  use Perl::Class;
  use base qw(Perl::Class::Hash);
  sub new {
    $_[0]->SUPER::new(1 => 2, 'odd');
  }
  1;

  package main;
  my $c = Foo->new();
  $c->{3} = 4;
  join ':', (keys %$c, '|', keys %{$c->__});

=cut
