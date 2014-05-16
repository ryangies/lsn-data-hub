package App::Console::CommandScript;
use strict;
our $VERSION = 0;

use Perl::Module;
use Error qw(:try);
use Error::Simple;
use Error::Programatic;
use Data::Hub::Util qw(path_name);
use App::Console::Color qw(:all);

our %USAGE = ();

sub new {
  bless {}, ref($_[0]) || $_[0];
}

# ------------------------------------------------------------------------------
# exec - Invoke the subroutine in the derived class, or display help
# exec @args
# ------------------------------------------------------------------------------

sub exec {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my ($opts, @args) = my_opts(\@_);
  my $cmd = shift @args;
  $self->{OPTS} = $opts;
  if ($opts->{help}) {
    $cmd ||= $opts->{help};
    undef $cmd if $cmd eq '1';
    $self->_help($cmd);
  } else {
    return $self->_help unless $cmd;
    throw Error::Simple "No such command: $cmd (try -help)\n"
      unless $self->can($cmd);
    try {
      $self->$cmd(@args, -opts => $opts);
    } catch Error with {
      return if $$opts{quiet};
      my $ex = shift;
      warn isa($ex, 'SCALAR') ? $$ex : $ex;
    }
  }
}

sub _help {
  my $self = shift;
  my $cmd = shift;
  my $name = path_name($0);
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $usage = eval('\%' . ref($self) . '::USAGE');
  print STDERR "usage:\n";
  if ($cmd && $usage->{$cmd}) {
    my $cmd_usage = $usage->{$cmd};
    my @cmd_opts = grep {$_ =~ /^-/} keys %{$cmd_usage->{params}};
    my @cmd_args = grep {$_ !~ /^-/} keys %{$cmd_usage->{params}};
    my $width = List::Util::max(10, map { length($_) } keys %{$cmd_usage->{params}});
    print STDERR '  ', $name, ' ', $cmd;
    @cmd_args and c_printf \*STDERR, " %_bs", join (' ', @cmd_args);
    @cmd_opts and c_printf \*STDERR, " %_gs", '[options]';
    print STDERR "\n";
    if (@cmd_args) {
      print STDERR "where:\n";
      foreach my $k (@cmd_args) {
        c_printf \*STDERR, "  %_b-${width}s %s\n", $k, $cmd_usage->{params}{$k};
      }
    }
    print STDERR "options:\n";
    c_printf \*STDERR, "  %_g-${width}s %s\n", '-quiet', 'Suppress errors and warnings';
    if (@cmd_opts) {
      foreach my $k (@cmd_opts) {
        c_printf \*STDERR, "  %_g-${width}s %s\n", $k, $cmd_usage->{params}{$k};
      }
    }
    if ($cmd_usage->{more}) {
      print $cmd_usage->{more};
    }
  } else {
    c_printf \*STDERR, "  $name -help [%_bs]\n", 'command';
    c_printf \*STDERR, "  $name %_bs [arguments] [options]\n", '<command>';
    print STDERR "commands:\n";
    my $width = List::Util::max(10, map {length($_)} keys %$usage);
    c_printf(\*STDERR, "  %_b-${width}s %s\n", $_, $usage->{$_}{summary}) for sort keys %$usage;
  }
}

# ------------------------------------------------------------------------------
# warn - Print to STDERR (unless -quiet)
# warn @messages
# ------------------------------------------------------------------------------

sub warn {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  return if $self->{OPTS}{quiet};
  c_printf \*STDERR, '%_ms', join('', @_);
}

# ------------------------------------------------------------------------------
# print - Print to STDOUT (unless -quiet)
# print @messages
# ------------------------------------------------------------------------------

sub print {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  return if $self->{OPTS}{quiet};
  print STDOUT @_;
}

# ------------------------------------------------------------------------------
# printf - Print formatted output to STDOUT (unless -quiet)
# printf $spec, @parameters
# C<$spec> may contain color conversions (See L<App::Console::Color>)
# ------------------------------------------------------------------------------

sub printf {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  return if $self->{OPTS}{quiet};
  c_printf \*STDOUT, @_;
}

# ------------------------------------------------------------------------------
# err_print - Print to STDERR (unless -quiet)
# err_print @messages
# ------------------------------------------------------------------------------

sub err_print {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  return if $self->{OPTS}{quiet};
  print STDERR @_;
}

# ------------------------------------------------------------------------------
# err_printf - Print formatted output to STDERR (unless -quiet)
# err_printf $spec, @parameters
# C<$spec> may contain color conversions (See L<App::Console::Color>)
# ------------------------------------------------------------------------------

sub err_printf {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  return if $self->{OPTS}{quiet};
  c_printf \*STDERR, @_;
}

# ------------------------------------------------------------------------------
# fail - Exit the program with an optional message
# fail
# fail @messages
# When C<@messages> are provided (and not C<-quiet>), C<die> is called and help
# verbiage is appened. Otherwise C<exit> is called with a value of C<1>.
# ------------------------------------------------------------------------------

sub fail {
  my $self = shift;
  @_ and die @_, " (use -help for help).\n" unless $self->{OPTS}{quiet};
  exit 1;
}

# ------------------------------------------------------------------------------
# quit - Exit the program (not trappable) with an optional message
# quit
# quit @messages
# The C<@messages> are not written to STDERR if C<-quiet> is enabled.
# ------------------------------------------------------------------------------

sub quit {
  my $self = shift;
  if (@_ && !$self->{'OPTS'}{'quiet'}) {
    printf STDERR @_;
    printf STDERR "\n";
  }
  exit 1;
}

1;

=pod:synopsis

  #!/usr/bin/perl -w

  package Local::App;
  use strict;
  use Data::OrderedHash;
  use base 'App::Console::CommandScript';

  our %USAGE = ();

  sub new {
    my $self = shift->SUPER::new();
    $self;
  }

  $USAGE{'test'} = {
    summary => 'My test command',
    params => Data::OrderedHash->new(
      '<param>' => 'This is a required parameter',
      '-foo' => 'This is an option',
    ),
  };

  sub test {
    my $self = shift;
    my $opts = my_opts(\@_);
    my $param = shift;
    my $foo = $opts->{foo} || 'unset';
    $self->printf("You passed in '%s' and -foo is '%s'\n", $param, $foo)
  };

  1;

  package main;
  Local::App->new()->exec(@ARGV);

=pod:description

This package faciltates writing command-line scripts.  The base class method 
C<exec> looks to your package for the C<%USAGE> hash to display command usage 
and glean the required syntax.  A command is simply a method which exists in 
your package.

If the above example were placed in an executable file name 'mycmd.pl', then:

  $ ./mycmd.pl

  usage:
    mycmd.pl -help [command]
    mycmd.pl <command> [arguments] [options]
  commands:
    test       My test command

  $ ./mycmd.pl -help test

  usage:
    mycmd.pl test <param> [options]
  where:
    <param>    This is a required parameter
  options:
    -quiet     Suppress errors and warnings
    -foo       This is an option

Notice the global option C<-quiet> which affects the base methods

  print
  printf
  err_print
  err_printf
  fail

=cut
