=head1 NAME

XAO::DO::Web::Mailer - executes given template and sends results via e-mail

=head1 SYNOPSIS

 <%Mailer
   to="foo@somehost.com"
   from="bar@otherhost.com"
   subject="Your order '<%ORDER_ID/f%>' has been shipped"
   text.path="/bits/shipped-mail-text"
   html.path="/bits/shipped-mail-html"
   ORDER_ID="<%ORDER_ID/f%>"
 %>

=head1 DESCRIPTION

Displays nothing, just sends message.

Arguments are:

 to          => e-mail address of the recepient; default is taken from
                userdata->email if defined.
 cc          => optional e-mail addresses of secondary recepients
 from        => optional 'from' e-mail address, default is taken from
                'from' site configuration parameter.
 subject     => message subject;
 [text.]path => text-only template path (required);
 html.path   => html template path;
 date        => optional date header, passed as is
 ARG         => VALUE - passed to Page when executing templates;

If 'to', 'from' or 'subject' are not specified then get_to(), get_from()
or get_subject() methods are called first. Derived class may override
them. 'To' and 'cc' may be comma-separated addresses lists.

The configuration for Web::Mailer is kept in a hash stored in the site
configuration under 'mailer' name. Normally it is not required, the
default is to use sendmail for delivery. The parameters are:

 method      => either 'local' or 'smtp'
 agent       => server name for `smtp' or binary path for `local'
 from        => either a hash reference or a scalar with the default
                `from' address.
 override_to => if set overrides all to addresses and always sends to
                the given address. Useful for debugging.

If `from' is a hash reference then the content of `from' argument to the
object is looked in keys and the value is used as actual `from'
address. This can be used to set up rudimentary aliases:

 <%Mailer
   ...
   from="customer_support"
   ...
 %>

 mailer => {
    from => {
        customer_support => 'support@foo.com',
        technical_support => 'tech@foo.com',
    },
    ...
 }

In that case actual from address will be `support@foo.com'. By default
if `from' in the configuration is a hash and there is no `from'
parameter for the object, `default' is used as the key.

=cut

###############################################################################
package XAO::DO::Web::Mailer;
use strict;
use MIME::Lite 2.117;
use XAO::Utils;
use XAO::Errors qw(XAO::DO::Web::Mailer);
use base XAO::Objects->load(objname => 'Web::Page');

use vars qw($VERSION);
$VERSION=(0+sprintf('%u.%03u',(q$Id: Mailer.pm,v 2.1 2005/01/14 01:39:57 am Exp $ =~ /\s(\d+)\.(\d+)\s/))) || die "Bad VERSION";

sub display ($;%) {
    my $self=shift;
    my $args=get_args(\@_);

    my $config=$self->siteconfig->get('/mailer') || {};

    my $to=$args->{to} ||
           $self->get_to($args) ||
           throw $self "display - no 'to' given";

    if($config->{override_to}) {
        dprint ref($self)."::display - overriding '$to' with '$config->{override_to}'";
        $to=$config->{override_to};
    }

    my $from=$args->{from};
    if(!$from) {
        $from=$config->{from};
        $from=$from->{default} if ref($from);
    }
    else {
        $from=$config->{from}->{$from} if ref($config->{from}) &&
                                          $config->{from}->{$from};
    }
    $from || throw $self "display - no 'from' given";

    my $from_hdr=$from;
    if($from =~ /^\s*.*\s+<(.*\@.*)>\s*$/) {
        $from=$1;
    }
    elsif($from =~ /^\s*(.*\@.*)\s+\(.*\)\s*$/) {
        $from=$1;
    }
    else {
        $from=~s/^\s*(.*?)\s*$/$1/;
    }

    my $subject=$args->{subject} || $self->get_subject() || 'No subject';

    ##
    # Parsing text template
    #
    my $page=$self->object;
    my $text;
    if($args->{'text.path'} || $args->{path} ||
       $args->{'text.template'} || $args->{template}) {
        my $objargs=merge_refs($args, {
            path        => $args->{'text.path'} || $args->{path},
            template    => $args->{'text.template'} || $args->{template},
        });
        $text=$page->expand($objargs);
    }
    
    ##
    # Parsing HTML template
    #
    my $html;
    if($args->{'html.path'} || $args->{'html.template'}) {
        my $objargs=merge_refs($args,{
            path        => $args->{'html.path'},
            template    => $args->{'html.template'},
        });
        $html=$page->expand($objargs);
    }

    ##
    # Preparing mailer and storing content in
    #
    my $mailer;
    if($html && !$text) {
        $mailer=MIME::Lite->new(
            From        => $from_hdr,
            FromSender  => $from,
            To          => $to,
            Subject     => $subject,
            Data        => $html,
            Type        => 'text/html',
            Datestamp   => 0,
            Date        => $args->{'date'} || undef,
        );
    }
    elsif($text && !$html) {
        $mailer=MIME::Lite->new(
            From        => $from_hdr,
            FromSender  => $from,
            To          => $to,
            Subject     => $subject,
            Data        => $text,
            Datestamp   => 0,
            Date        => $args->{'date'} || undef,
        );
    }
    elsif($text && $html) {
        $mailer=MIME::Lite->new(
            From        => $from_hdr,
            FromSender  => $from,
            To          => $to,
            Subject     => $subject,
            Type        => 'multipart/alternative',
            Datestamp   => 0,
            Date        => $args->{'date'} || undef,
        );
        $mailer->attach(
            Type        => 'text/html',
            Data        => $html,
        );
        $mailer->attach(
            Type        => 'text/plain',
            Data        => $text,
        );
    }
    else {
        throw $self "display - no text for either html or text part";
    }
    $mailer->add(Cc => $args->{cc}) if $args->{cc};

    ##
    # Sending
    #
    ### dprint $mailer->as_string;
    my $method=$config->{method} || 'local';
    my $agent=$config->{agent};
    if(lc($method) eq 'local') {
        if($agent) {
            $mailer->send('sendmail',$agent);
        }
        else {
            $mailer->send('sendmail');
        }
    }
    else {
        $mailer->send('smtp',$agent || 'localhost');
    }
}

###############################################################################

sub get_to ($%) {
    return '';
}

###############################################################################

sub get_from ($%) {
    return '';
}

###############################################################################

sub get_subject ($%) {
    return '';
}

###############################################################################
1;
__END__

=head1 METHODS

No publicly available methods except overriden display().

=head1 EXPORTS

Nothing.

=head1 AUTHOR

Copyright (c) 2005 Andrew Maltsev

Copyright (c) 2001-2004 Andrew Maltsev, XAO Inc.

<am@ejelta.com> -- http://ejelta.com/xao/

=head1 SEE ALSO

Recommended reading:
L<XAO::Web>,
L<XAO::DO::Web::Page>.
