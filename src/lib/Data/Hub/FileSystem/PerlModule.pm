package Data::Hub::FileSystem::PerlModule;
use strict;
use Perl::Module;
use Data::Hub::Util qw(:all);
use Error::Programatic;
use Error::Logical;
use base qw(Data::Hub::FileSystem::TextFile);

sub get_package {
  my $self = shift;
  my $tied = tied(%$self);
  $tied->__scan();
  $tied->__private->{package_name};
}

# ------------------------------------------------------------------------------
# __content - Get/Set file contents
# __content
# __content \$new_content
# ------------------------------------------------------------------------------

sub __content {
  my $tied = shift;
  my $c = undef;
  if (exists $_[0]) {
    # Set
    $c = $tied->SUPER::__content(@_);
    $tied->__parse_content;
  } else {
    # Get
    $c = $tied->SUPER::__content;
  }
  $c;
}

# ------------------------------------------------------------------------------
# FETCH - Get subroutine
# FETCH $sub_name
#
# Note, do not eval, i.e., require, the contents until a sub is invoked. This 
# is a security consideration, as eval is obviously dangerous. The intention 
# is that one can access the contents of the file using this FileSystem  object,
# without its contents being eval'd.
#
# The downside is that we will return a valide CODE reference no matter what
# key is being fetched. This could be handled with some /^sub\s+(\w+)/ type
# magic in __parse_content.
# ------------------------------------------------------------------------------

sub FETCH {
  my $tied = shift;
  my $sub_name = shift;
  return sub {
    $tied->__scan($sub_name);
    $tied->__use_content unless $tied->__private->{ok};
    if ($tied->__private->{ok}) {
      my $pkg_name = $tied->__private->{package_name};
      if (can($pkg_name, $sub_name)) {
          $tied->__hub and unshift @{$tied->__hub->__dir_stack},
            addr_parent($tied->__addr);
          local $SIG{'__WARN__'} = sub {$tied->__sig_warn(@_)};
          local $SIG{'__DIE__'} = sub {$tied->__sig_die(@_)};
          no strict qw(refs);
          if (can($pkg_name, 'ACCESS')) {
            #
            # If the ACCESS method returns true, we will execute the requested
            # subroutine (and any others requested during this checkpoint).
            #
            # Package Variables Feature
            #
            # Because this is only called once for each checkpoint (i.e., request), 
            # one may set shared package variables.  This way, even if a routine
            # like "get_context" is called 100 times in the request, the work of
            # getting the context can be done only once:
            #
            #   our %Context = ();
            #   sub ACCESS {
            #     %Context = ();                # always reset!
            #     return unless has_privs();    # deny unless auth
            #     %Context = (
            #       ...                         # do the work
            #     );
            #     1;                            # allow access
            #   }
            #
            # Note that the 'always reset' step does two things:
            #
            #   1) When not authorized, the data from the last request is
            #      discarded.  This could be done in a cleanup method, however
            #      knowing when to call cleanup is not always clear, hence it
            #      is not implemented.
            #
            #   2) When running under an Apache2 web server with mod_perl in
            #      "developer mode" (meaning the same process serves up multiple
            #      domains/vhosts) this package variable may contain data from
            #      an entirely different host!
            #
            my $tied_cp = $tied->__checkpoint;
            my $access_cp = $tied->__private->{access_cp};
            if (!defined($access_cp) || $access_cp < $tied_cp) {
  #           warn "Querying ACCESS to $sub_name at checkpoint $tied_cp\n";
              my $sub = $pkg_name . '::ACCESS';
              throw Error::AccessDenied("${pkg_name}::ACCESS")
                unless &$sub();
                # 
                # unless &$sub($sub_name, @_);
                #
                # Originally I thought it useful to call ACCESS once for each
                # subroutine.  The idea being that one could use the sub name
                # to escalate credentials, e.g., subs which start with 'set_'
                # are resricted and those which start with '_' are denied.
                #
                # In practice, this simply adds move overhead than its worth.
                # Once can simply insert the helper code at the beginning of
                # each function.  Additionally, doing this once per sub would
                # defeat the once-per-request-package-vars feature (above).
                #
              $tied->__private->{access_cp} = $tied_cp;
            } else {
  #           warn "Already allowed ACCESS to this module ($pkg_name).\n";
            }
          }
          my $sub = $pkg_name . '::' . $sub_name;
          my $result = $sub_name eq 'new'
            ? $pkg_name->new(@_)
            : &$sub(@_);
          $tied->__hub and shift @{$tied->__hub->__dir_stack};
          $result;
      }
    }

  }
}

# ------------------------------------------------------------------------------
# STORE - Store subroutine value, fatal error!
# ------------------------------------------------------------------------------

sub STORE {
  throw Error::Programatic 'Perl subroutines cannot be stored';
}

# ------------------------------------------------------------------------------
# __use_content - Eval file contents (use as a module)
# __use_content
# The package name is determined from its absolute path
# ------------------------------------------------------------------------------

sub __use_content {
  my $tied = shift;
  {
    no warnings qw(redefine);
    local $!;
    local $@;
    local $SIG{'__WARN__'} = sub {$tied->__sig_warn(@_)};
    local $SIG{'__DIE__'} = sub {$tied->__sig_die(@_)};
    # Put local directory in directory stack for @INC resolution
    $tied->__hub and unshift @{$tied->__hub->__dir_stack},
      addr_parent($tied->__addr);
    # Hook in to @INC mechism with current scope
    unshift @INC, [\&__require_hook, $tied];
    # Unload if currently loaded
    $tied->__unload();
    # Eval, i.e., require, the module
    #
    #   XXX: We could use the Safe module, however the context switching of the
    #   package name doesn't work. Need a Safe::Require module...
    #
    #   Additionally, using Safe CANNOT protect you from malicious modules, 
    #   i.e., user contributed content with dangerous code. This cannot be 
    #   prevented here.
    #
    $tied->__private->{ok} = eval $tied->__private->{parsed_content};
    # Remove our hook
    shift @INC;
    # Remove local directory from directory stack
    $tied->__hub and shift @{$tied->__hub->__dir_stack};
    warn $@ if $@;
    throwf Error::Programatic("%s did not return a true value\n", $tied->__path)
      unless $tied->__private->{ok};
  }
  $tied->__private->{ok};
}

# ------------------------------------------------------------------------------
# __require_hook - Evaluate paths in current Hub scope
# __require_hook $tied_hub
#
# Apache2::Reload considers every value in %INC to be a file path.  By default
# the hook is placed in %INC in place of the file name (see %INC in perlvar).
# Apache2::Reload will issue a warning when trying to reload the array, so we
# set the %INC entry ourselves.
# ------------------------------------------------------------------------------

sub __require_hook {
  my (undef, $tied) = @{$_[0]};
  my $hub = $tied->__hub;
  my $res = $hub->FETCH($_[1]) or return;
  my $path = $res->get_path();
  my $h = IO::File->new('<' . $path) or die "$!: $path";
  $INC{$_[1]} = $path;
  $tied->__private->{deps} ||= [];
  push @{$tied->__private->{deps}}, $res;
  $tied->__access_log->set_value($path, $res->get_mtime);
  return $h;
}

# ------------------------------------------------------------------------------
# __scan - Read from disk if necessary
# __scan
# ------------------------------------------------------------------------------

sub __scan {
  my $tied = shift;
  my $reload = $tied->SUPER::__scan(@_);
  return $reload if $reload;
  if ($tied->__private->{deps}) {
    foreach my $dep (@{$tied->__private->{deps}}) {
      $reload = $dep->refresh();
#warn "checking dep: ", $dep->get_addr, " ($reload)\n";
      last if $reload;
    }
  }
  $reload and $tied->__read_from_disk();
  return $reload;
}

# ------------------------------------------------------------------------------
# __parse_content - Generate dynamic package name
# __parse_content
#
# The perl-module should begin with (on its own line!):
#
#   # PerlModule
#
# which will be replaced with:
#
#   package _home_user_test_module_pm;
#
# presuming the file is located at /home/user/test/module.pm
#
# Note:
#
#   .-------------------  No whitespace is allowed before the pound-sign (#)
#   v
#   # PerlModule
#    ^
#    '------------------  Whitespace between the pound-sign and first word is 
#                         optional.
#
# If the content defines a package, e.g., C<package Local;> no modification is
# performed.
#
# If the content does not include the C<# PerlModule> crown, it will be 
# inserted.
#
# DEPRICATED
#
# If the first line is:
#
#   package PACKAGE;
#
# it will be replaced with the dynamic package name.
# ------------------------------------------------------------------------------

sub __parse_content {
  my $tied = shift;
  $tied->__private->{parsed_content} = undef;
  $tied->__private->{ok} = undef;
  return unless $tied->__content;
  my $pkg_name = $tied->__path;
  $pkg_name =~ s/[\s\W]/_/g;
  $tied->__private->{package_name} = $pkg_name;
  my $content = ${$tied->__content};
  my ($name) = $content =~ /^package\s+([\S]+);?/m;
  # The trailing '#' is to allow for extended syntax, e.g., '# PerlModule v:1.1'
  unless ($content =~ s/^#\s*PerlModule\b/package $pkg_name; #/) {
    $content = "package $pkg_name;\n# line 1\n$content";
  }
  $tied->__private->{parsed_content} = $content;
  $content;
}

# ------------------------------------------------------------------------------
# __sig_warn - Replace '(eval ##)' with file name
# __sig_warn $message
# ------------------------------------------------------------------------------

sub __sig_warn {
  my $tied = shift;
  my $msg = shift;
  my $path = $tied->__addr;
  $msg =~ s/\(eval (\d+)\)/$path/;
  $msg =~ s/at \/loader\/[xa-f0-9]+\//at /i;
  warn $msg;
}

# ------------------------------------------------------------------------------
# __sig_die - Replace '(eval ##)' with file name
# __sig_die $message
# ------------------------------------------------------------------------------

sub __sig_die {
  my $tied = shift;
  my $msg = shift;
  my $path = $tied->__addr;
  $msg =~ s/\(eval (\d+)\)/$path/;
  $msg =~ s/at \/loader\/[xa-f0-9]+\//at /i;
  die $msg;
}

# ------------------------------------------------------------------------------
# __unload - Unload a previously loaded package from this file path
# __unload
# Taken from ModPerl::Util::unload_package_pp
# ------------------------------------------------------------------------------

sub __unload {
    my $tied = shift;
    my $package = $tied->__private->{package_name} or return;

    no strict 'refs';
    my $tab = \%{ $package . '::' };

    # below we assign to a symbol first before undef'ing it, to avoid
    # nuking aliases. If we undef directly we may undef not only the
    # alias but the original function as well

    for (keys %$tab) {
        #Skip sub stashes
        next if /::$/;

        my $fullname = join '::', $package, $_;
        # code/hash/array/scalar might be imported make sure the gv
        # does not point elsewhere before undefing each
        if (%$fullname) {
            *{$fullname} = {};
            undef %$fullname;
        }
        if (@$fullname) {
            *{$fullname} = [];
            undef @$fullname;
        }
        if ($$fullname) {
            my $tmp; # argh, no such thing as an anonymous scalar
            *{$fullname} = \$tmp;
            undef $$fullname;
        }
        if (defined &$fullname) {
            no warnings;
            local $^W = 0;
            if (defined(my $p = prototype $fullname)) {
                *{$fullname} = eval "sub ($p) {}";
            }
            else {
                *{$fullname} = sub {};
            }
            undef &$fullname;
        }
        if (*{$fullname}{IO}) {
            local $@;
            eval {
                if (fileno $fullname) {
                    close $fullname;
                }
            };
        }
    }

    #Wipe from %INC
    $package =~ s[::][/]g;
    $package .= '.pm';
    delete $INC{$package};
}

1;

__END__

=pod:description

PerlModule now inserts an @INC hook which looks for your file in Hub context.
Meaning, you may now:

  require '/web/scripts/util.pm';
  require '../shared.pm';
  require './share.pm';

from within your module.  Note that this hook is inserted at beginning of @INC
and will be run first.  Modules which exist in the same directory as the calling
module must be prefixed with './', as in:

  require './share.pm'; # correct
  require 'share.pm';   # not found

When calling routines, if the module has defined an ACCESS function, it will be
called (once per checkpoint) before calling a routine.

  sub ACCESS {
    return 1;   # return true (access allowed) or false (access denied)
  }

=cut
