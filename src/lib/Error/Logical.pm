package Error::Logical;
use strict;
our $VERSION = 0;
use base qw(Error::Programatic);

# ------------------------------------------------------------------------------
# new - Constructor
# ------------------------------------------------------------------------------
#|test(abort)
#|use Error::Logical;
#|throw Error::DoesNotExist 'some resource';
# ------------------------------------------------------------------------------

sub ex_prefix {'Logical Error'}
1;

package Error::MissingParam;
use base qw(Error::Logical);
sub ex_prefix{'Missing parameter'}
1;

package Error::IllegalParam;
use base qw(Error::Logical);
sub ex_prefix{'Illegal parameter'}
1;

package Error::DoesNotExist;
use base qw(Error::Logical);
sub ex_prefix{'Resource does not exist'}
1;

package Error::AccessDenied;
use base qw(Error::Logical);
sub ex_prefix{'Access denied'}
1;

package Error::Security;
use base qw(Error::Logical);
sub ex_prefix{'Security violation'}
1;

package Error::Continue;
use base qw(Error::Logical);
sub ex_prefix{'Continue processing'}
1;

package Error::HttpsRequired;
use base qw(Error::Logical);
sub ex_prefix{'An HTTPS connection is required'}
1;

package Error::HttpsNotRequired;
use base qw(Error::Logical);
sub ex_prefix{'An HTTPS connection is NOT required'}
1;
