package Perl::Clone;
use strict;
our $VERSION = 0.1;

use Exporter;
use Carp qw(croak);
use Data::OrderedHash;

our @EXPORT_OK = qw(clone overlay);
our %EXPORT_TAGS = (all => [@EXPORT_OK],);
push our @ISA, qw(Exporter);

# ------------------------------------------------------------------------------
# clone - Recursively clone the reference, returning a new reference.
# clone $item
# clone \$item, [$create]
# clone \%item, [$create]
# clone \@item, [$create]
#
# where:
#
#   $create               Specifies the constructor to use for creating new
#                         objects.  Default is: -copy_ref
#
#         -keep_order     Use Data::OrderedHash for creating hashes
#         -copy_ref       Call C<new> on the source structure reference
#         -pure_perl      Use {}, [], \'' for creating new objects
#         \%hash          Provide your own constructors
#
# Implemented because the Clone module found on CPAN crashes under my mod_perl 
# and FastCGI test servers.
#
# The constructor-hash looks like:
#
#   our %PerlStructs = (
#     'HASH' => sub {return {};},
#     'ARRAY' => sub {return [];},
#     'SCALAR' => sub {my $s = ''; return \$s},
#   );
#
# The C<ref()> of the source structure is passed as the first argument to the
# constructor-hash subroutine.
#
# ------------------------------------------------------------------------------

our %PerlStructs = (
  'HASH' => sub {return {};},
  'ARRAY' => sub {return [];},
  'SCALAR' => sub {my $s = ''; return \$s},
);

our %OrderedStructs = (
  'HASH' => sub {return Data::OrderedHash->new;},
  'ARRAY' => sub {return [];},
  'SCALAR' => sub {my $s = ''; return \$s},
);

use Try::Tiny;

our %CopyStructs = (
  'HASH' => sub {my $r = shift; $r eq 'HASH' ? {} : new $r;},
  'ARRAY' => sub {my $r = shift; $r eq 'ARRAY' ? [] : new $r;},
  'SCALAR' => sub {
    my $r = shift;
    my $s = '';
    return try {
      $r eq 'SCALAR' ? \$s : new $r;
    } catch {
      \$s;
    };
  },
);

sub clone {
  my $create = $_[1]
    ? ref($_[1]) ? $_[1] :
      $_[1] eq '-keep_order' ? \%OrderedStructs :
      $_[1] eq '-copy_ref' ? \%CopyStructs :
      $_[1] eq '-pure_perl' ? \%PerlStructs : undef
    : \%CopyStructs;
  die "Invalid option: $_[1]\n" unless $create;
  _clone($_[0], $create);
}

sub _clone {
  my $ref = shift;
  my $create = shift;
  return $ref unless ref($ref);
  my $new = ();
  if (UNIVERSAL::isa($ref, 'HASH')) {
    $new = &{$create->{'HASH'}}(ref($ref));
    keys %$ref; # reset iterator
    while( my($k,$v) = each %$ref ) {
      if( ref($v) ) {
        $new->{$k} = _clone($v, $create) unless $v eq $ref;
      } else {
        $new->{$k} = $v;
      }
    }
  } elsif (UNIVERSAL::isa($ref, 'ARRAY')) {
    $new = &{$create->{'ARRAY'}}(ref($ref));
    foreach my $v ( @$ref ) {
      if( ref($v) ) {
        push @$new, _clone($v, $create);
      } else {
        push @$new, $v;
      }
    }
  } elsif (UNIVERSAL::isa($ref, 'SCALAR')) {
    $new = &{$create->{'SCALAR'}}(ref($ref));
    $$new = $$ref;
  } elsif (ref($ref) eq 'REF') {
    $$ref eq $ref and
      warn "Self reference cannot be copied: $ref";
    ($$ref ne $ref) and $new = _clone($$ref, $create);
  } elsif (ref($ref) eq 'CODE') {
    $new = $ref;
  } else {
    croak "Cannot copy reference: $ref\n";
  }
  return $new;
}

our %NoClone = (
  'HASH' => sub {$_[0]},
  'ARRAY' => sub {$_[0]},
  'SCALAR' => sub {$_[0]},
);

# ------------------------------------------------------------------------------
# overlay - Overlay one structre on top of another
# overlay \%left, \%right, [$create]
# overlay \@left, \@right, [$create]
# @see L</clone> for C<$create> option.
#   -no_clone   Do not clone values
# ------------------------------------------------------------------------------

sub overlay {
  my $create = $_[2]
    ? ref($_[2]) ? $_[2] :
      $_[2] eq '-keep_order' ? \%OrderedStructs :
      $_[2] eq '-copy_ref' ? \%CopyStructs :
      $_[2] eq '-no_clone' ? \%NoClone :
      $_[2] eq '-pure_perl' ? \%PerlStructs : undef
    : \%CopyStructs;
  die "Invalid option: $_[2]\n" unless $create;
  _overlay($_[0], $_[1], $create);
}

sub _overlay {
  my $new = shift;
  my $ref = shift;
  my $create = shift;
  return $ref unless ref($ref);
  if (UNIVERSAL::isa($ref, 'HASH')) {
    $new = &{$create->{'HASH'}}(ref($ref)) unless UNIVERSAL::isa($new, 'HASH');
    keys %$ref; # reset iterator
    while (my($k,$v) = each %$ref) {
      if (ref($v)) {
        $new->{$k} = _overlay($new->{$k}, $v, $create) unless $v eq $ref;
      } else {
        $new->{$k} = $v;
      }
    }
  } elsif (UNIVERSAL::isa($ref, 'ARRAY')) {
    $new = &{$create->{'ARRAY'}}(ref($ref)) unless UNIVERSAL::isa($new, 'ARRAY');
    foreach my $v (@$ref) {
      if( ref($v) ) {
        push @$new, _clone($v, $create);
      } else {
        push @$new, $v;
      }
    }
  } elsif (UNIVERSAL::isa($ref, 'SCALAR')) {
    $new = &{$create->{'SCALAR'}}(ref($ref)) unless UNIVERSAL::isa($new, 'SCALAR');
    $$new = $$ref;
  } elsif (ref($ref) eq 'REF') {
    if ($$ref eq $ref) {
      warn "Self reference cannot be copied: $ref";
    } else {
      $new = _clone($$ref, $create);
    }
  } elsif (ref($ref) eq 'CODE') {
    $new = $ref;
  } else {
    croak "Cannot merge reference: $ref\n";
  }
  return $new;
}

1;

__END__
