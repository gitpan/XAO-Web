=head1 NAME

XAO::DO::Web::Date - XAO::Web date dysplayable object

=head1 SYNOPSIS

 <%Date%>

 <%Date gmtime="123456789" style="short"%>

 <%Date format="%H:%M"%>

 <%Date gmtime="123456789" timezone="US/Eastern"%>

=cut

###############################################################################
package XAO::DO::Web::Date;
use strict;
use POSIX qw(strftime);
use XAO::Utils;
use XAO::Objects;
use base XAO::Objects->load(objname => 'Web::Page');

use vars qw($VERSION);
($VERSION)=(q$Id: Date.pm,v 1.6 2003/02/12 03:18:49 am Exp $ =~ /(\d+\.\d+)/);

###############################################################################

=head1 DESCRIPTION

Displays current or given date. Arguments are:

=over

=item gmtime

Number of seconds since the Epoch (unix standard time). Optional,
default is to display the current time.

=item style

Display according to one of internal styles:

 dateonly   => %m/%d/%Y             => 3/27/2002
 short      => %H:%M:%S %m/%d/%Y    => 12:23:34 3/27/2002
 timeonly   => %H:%M:%S             => 12:23:34

=item format

Set custom format according to strftime C function API.

=item timezone

May contain a name of a time zone, which must be known to the
system. Default is the default system timezone.

=back

=cut

sub display ($;%) {
    my $self=shift;
    my $args=get_args(\@_);

    ##
    # Setting timezone
    #
    my $tz;
    if($args->{timezone}) {
        $tz=$ENV{TZ};
        $ENV{TZ}=$args->{timezone};
    }

    ##
    # It can be current time or given time
    #
    my $time=$args->{gmtime} || time;

    ##
    # Checking output style
    #
    my $style=$args->{style} || '';
    my $format='';
    if(!$style) {
        $format=$args->{format};
    }
    elsif($style eq 'dateonly') {
        $format='%m/%d/%Y';
    }
    elsif($style eq 'short') {
        $format='%H:%M:%S %m/%d/%Y';
    }
    elsif($style eq 'timeonly') {
        $format='%H:%M:%S';
    }
    else {
        eprint "Unknown date style '$style'";
    }

    ##
    # Displaying according to format.
    #
    if($format) {
        $time=strftime($format,localtime($time));
    }
    else {
        $time=scalar(localtime($time));
    }

    $self->textout($time);

    ##
    # Restoring timezone
    #
    if($args->{timezone}) {
        if(defined $tz) {
            $ENV{TZ}=$tz;
        }
        else {
            delete $ENV{TZ};
        }
    }
}

###############################################################################
1;
__END__

=head1 METHODS

No publicly available methods except overriden display().

=head1 EXPORTS

Nothing.

=head1 AUTHOR

Copyright (c) 2000-2002 XAO, Inc.

Andrew Maltsev <am@xao.com>.

=head1 SEE ALSO

Recommended reading:
L<XAO::Web>,
L<XAO::DO::Web::Page>.

=cut
