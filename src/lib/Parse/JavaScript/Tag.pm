package Parse::JavaScript::Tag;
use strict;
use Perl::Module;

sub new {
  my $classname = ref($_[0]) ? ref(shift) : shift;
  my $self = bless {
    'tag_name' => shift,
    'tag_value' => shift,
    'tag_info' => shift,
  }, $classname;
}

sub unmarshal {
  my $self = shift;
  my $value = shift;
  %$self = %$value;
}

sub get_name {
  $_[0]->{'tag_name'};
}

sub get_value {
  $_[0]->{'tag_value'};
}

sub get_info {
  $_[0]->{'tag_info'};
}

sub is_instance_tag {
  my $self = shift;
  $self->{'tag_name'} eq 'instance';
}

# THIS DOES NOT TEST $self
sub is_context_tag {
  my $self = shift;
  $self->{'tag_name'} eq 'namespace';
}

sub is_class_tag {
  my $self = shift;
  $self->{'tag_name'} =~ /class$/; # class, subclass
}

1;
