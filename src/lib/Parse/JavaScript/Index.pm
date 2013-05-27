package Parse::JavaScript::Index;
use strict;
use Perl::Module;
use Parse::JavaScript::File;

sub new {
  my $classname = ref($_[0]) ? ref(shift) : shift;
  bless {
    'index' => {},
    'files' => [],
    'instances' => {},
  }, $classname;
}

sub add {
  my $self = shift;
  my @result = ();
  foreach my $path (@_) {
    my $file = Parse::JavaScript::File->new($path);
    foreach my $name ($file->get_provides) {
      $self->{'index'}{$name} ||= [];
      push @{$self->{'index'}{$name}}, $file;
      my $tag = $file->get_tag($name);
      if ($tag->get_name eq 'instance') {
        $self->{'instances'}{$name} = $file;
      }
    }
    push @{$self->{'files'}}, $file;
    push @result, $file;
  }
  return @result;
}

sub use {
  my $self = shift;
  my $root = shift;
  my @result = ();
  foreach my $struct (@{$root->{'files'}}) {
    my $file = Parse::JavaScript::File->new();
    $file->unmarshal($struct);
    foreach my $name ($file->get_provides) {
      $self->{'index'}{$name} ||= [];
      push @{$self->{'index'}{$name}}, $file;
    }
    push @{$self->{'files'}}, $file;
    push @result, $file;
  }
  return @result;
}

sub get_providers {
  my $self = shift;
  my $name = shift;
  my $list = $self->{'index'}{$name};
  unless ($list) {
    foreach my $instance_name (keys %{$$self{'instances'}}) {
      if ($name =~ /^$instance_name\b/) {
        $list = [$self->{'instances'}{$instance_name}];
      }
    }
  }
  $list;
}

sub get_files {
  return @{$_[0]->{'files'}};
}

1;
