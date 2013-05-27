package Parse::Template::Content;
use strict;
our $VERSION = 0;
sub new {
  my $class = ref($_[0]) ? ref(shift) : shift;
  my $self = bless {}, $class;
  %$self = @_;
#warn "ct keys: ", join(',',keys %$self), "\n";
  $self;
}
sub to_string {my $c = shift->{content}; defined $c ? $$c : $c};
# length - Used in binary bool operation, i.e. [#:if CONTENT]
sub length {my $c = shift->{content}; defined $c ? length($$c) : 0};
1;
