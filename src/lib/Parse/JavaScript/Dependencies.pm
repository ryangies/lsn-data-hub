package Parse::JavaScript::Dependencies;
use strict;
use Perl::Module;

sub new {
  my $classname = ref($_[0]) ? ref(shift) : shift;
  my $self = bless {
    'indexes' => [@_],
    'names' => {},
    'seen' => {},
  }, $classname;
  $self;
}

sub recurse {
  my $self = shift;
  foreach my $file (@_) {
    next if $self->{'seen'}{$file}; # no inf rec
    $self->{'seen'}{$file} = 1;
    foreach my $name ($file->get_provides) {
      $self->{'names'}{$name} = $file;
    }
    foreach my $name ($file->get_usages) {
      next if defined $self->{'names'}{$name};
      $self->{'names'}{$name} = 0; # defined yet missing
      foreach my $index (@{$self->{'indexes'}}) {
        my $providers = $index->get_providers($name) or next;
        my $provider = shift @$providers;
        if (@$providers) {
          my $msg = sprintf "Multiple providers for: %s\n%s\n",
            $name,
            join("\n", map {"\t" . $_->get_path} ($provider, @$providers));
          warn $msg;
        }
        $self->{'names'}{$name} = $provider;
        $self->recurse($provider);
        last;
      }
    }
  }
  $self;
}

sub get_names {
  return keys %{$_[0]{'names'}};
}

sub get_provider {
  return $_[0]{'names'}{$_[1]};
}

1;
