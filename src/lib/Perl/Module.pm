package Perl::Module;
use strict;
our $VERSION = 0;

use Exporter qw(import);
our @EXPORT = ();

# ------------------------------------------------------------------------------
# _reexport - Use a package, import and export the specified methods.
# _reexport $package_name, @methods
# _reexport $package_name, ':all'
#
# When C<:all> is specified, all methods included in the target package's
# C<@EXPORT_OK> (required) array are used.
# ------------------------------------------------------------------------------
#|test(!abort) use Perl::Module;
#|test(match) join "\n", sort @Perl::Module::EXPORT;
#=Dumper
#=blessed
#=bytesize
#=can
#=carp
#=checksum
#=clone
#=cluck
#=compare
#=confess
#=croak
#=gettimeofday
#=grep_first
#=grep_first_index
#=index_imatch
#=index_match
#=index_unescaped
#=int_div
#=is_numeric
#=isa
#=max
#=min
#=my_opts
#=overlay
#=push_uniq
#=reftype
#=sleep
#=sort_compare
#=sort_keydepth
#=stat
#=str_ref
#=strftime
#=strptime
#=time
#=tv_interval
#=unshift_uniq
#=warnf
# ------------------------------------------------------------------------------

sub _reexport($@) {
  my $pkg = shift;
  eval "use $pkg qw(@_)";
  $@ and die $@;
  if (@_ == 1 && $_[0] eq ':all') {
    no strict 'refs';
    push @EXPORT, @{"${pkg}::EXPORT_OK"};
  } elsif (@_ == 1 && $_[0] eq ':std') {
    no strict 'refs';
    push @EXPORT, @{"${pkg}::EXPORT_STD"};
  } else {
    push @EXPORT, @_;
  }
}

# Import/export symbols defined in core perl distributions

_reexport('Data::Dumper', qw(Dumper));
_reexport('Carp', qw(carp croak cluck confess));
_reexport('Scalar::Util', qw(blessed));
_reexport('Time::HiRes', qw(time gettimeofday tv_interval sleep));
_reexport('File::stat', qw(stat));
_reexport('List::Util', qw(max min));

# Import/export symbols defined in our distribution

_reexport('Perl::Util', qw(:std));
_reexport('Perl::Comparison', qw(:all));
_reexport('Perl::Options', qw(:all));
_reexport('Perl::Clone', qw(:all));

1;

__END__

=pod:summary Perl Module Development

=pod:synopsis

  use Perl::Module;
  print "Perl::Module exports these methods from other modules:\n\t";
  print join("\n\t", sort @Perl::Module::EXPORT), "\n";

=pod:description

This is a standard include which C<use>'s and re-exports core packages
and methods.

=pod:compatability

We use/export C<time> from L<|Time::HiRes> which returns milliseconds!

We use/export C<stat> from File::stat which returns an object reference!

=pod:notes

C<Perl::*> modules (which will be used from this package) must not use 
this package.

=cut
