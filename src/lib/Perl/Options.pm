package Perl::Options;
use strict;
our $VERSION = 0.1;

use Exporter;
use Carp qw(confess);

our @EXPORT_OK = qw(my_opts);
our %EXPORT_TAGS = (all => [@EXPORT_OK],);
push our @ISA, qw(Exporter);

# ------------------------------------------------------------------------------
# _parse_option - Get the option key (and value) from an argument array item.
# _parse_option $arg
# _parse_option \$arg
# If the argument is not an option key, the return is undef.
# ------------------------------------------------------------------------------

sub _parse_option (\$) {
  my $ref = ref($_[0]) ? $_[0] : \$_[0];
  $$ref =~ /^-{1,2}(\w|\w[\d\w_]{1,64})(?:=(.*))?$/;
}

# ------------------------------------------------------------------------------
# opts - Subroutine parameter parser
# opts @_
# opts @_, %defaults
# ------------------------------------------------------------------------------
=test(match)
  my $sub = sub {
    my ($opts, @argv) = my_opts(\@_);
    my $ret = join(',', sort(@_));
    $ret .= ';' . join(',', sort keys %$opts);
    return $ret;
  };
  &$sub('a', 'b', '-opt1', -opt2 => 'See', '-opt3=0');
=result
  a,b;opt1,opt2,opt3
=cut
## ------------------------------------------------------------------------------

sub my_opts {
  my ($args, $defaults, $expand) = @_;
  my $opts = $defaults || {};
  for (my $i = 0; $i < @$args; $i++) {
    next unless defined $$args[$i];
    next if ref $$args[$i];
    my ($k, $v) = _parse_option($$args[$i]);
    next unless $k;
    my $eat = 0;
    if ($k eq 'opts') {
      # Next argument is exptect to be a hash of options.  Used for passing
      # already-parsed options from one function to another.
      $$opts{$_} = $$args[$i + 1]{$_} for keys %{$$args[$i + 1]};
      $eat = 2;
    } elsif (defined($v)) {
      # The argument is a scalar such as "-level=one" or "--level=one".  This
      # is not used as much in functions as it is on the command line.
      $opts->{$k} = $v;
      $eat = 1;
    } else {
      # The argument specifies an option, used as
      # -level => "one" or --level => "one".
      if ($i == $#$args) {
        # When it's the last argument, the value is simply 1
        $v = 1;
        $eat = 1;
      } else {
        # If the next argument is an option, the value is simply 1, otherwise
        # the next argument is the value.
        if (defined $$args[$i+1] && _parse_option($$args[$i+1])) {
          $v = 1;
          $eat = 1;
        } else {
          $v = $$args[$i+1];
          $eat = 2;
        }
      }
      if (exists $$opts{$k} && $expand) {
        my $cv = $$opts{$k};
        if (isa($cv, 'ARRAY')) {
          push @$cv, $v;
        } else {
          $opts->{$k} = [$cv, $v];
        }
      } else {
        $opts->{$k} = $v;
      }
    }
    if ($eat) {
      splice @$args, $i, $eat;
      $i--;
    };
  }
  return wantarray ? ($opts, @$args) : $opts;
}

1;

__END__
