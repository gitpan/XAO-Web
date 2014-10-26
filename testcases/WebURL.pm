package testcases::WebURL;
use strict;
use CGI;
use XAO::Utils;
use XAO::Web;

use base qw(testcases::base);

###############################################################################

sub test_all {
    my $self=shift;

    $ENV{DOCUMENT_ROOT}='/tmp';
    $ENV{GATEWAY_INTERFACE}='CGI/1.1';
    $ENV{HTTP_HOST}='www.xao.com';
    $ENV{HTTP_USER_AGENT}='Mozilla/5.0';
    $ENV{PATH_INFO}='/test/WebURL.html';
    $ENV{QUERY_STRING}='a=1&b=2';
    $ENV{REMOTE_ADDR}='127.0.0.1';
    $ENV{REMOTE_PORT}='12345';
    $ENV{REQUEST_METHOD}='GET';
    $ENV{REQUEST_URI}='/WebURL.html';
    $ENV{SCRIPT_FILENAME}='/usr/local/xao/handlers/xao-apache.pl';
    $ENV{SCRIPT_NAME}='';
    $ENV{SCRIPT_URI}='http://www.xao.com/WebURL.html';
    $ENV{SCRIPT_URL}='/WebURL.html';
    $ENV{SERVER_ADDR}='127.0.0.1';
    $ENV{SERVER_ADMIN}='am@xao.com';
    $ENV{SERVER_NAME}='xao.com';
    $ENV{SERVER_PORT}='80';
    $ENV{SERVER_PROTOCOL}='HTTP/1.1';
    $ENV{SERVER_SOFTWARE}='Apache/1.3.26 (Unix)';

    my $cgi=CGI->new;

    my $site=XAO::Web->new(sitename => 'test');
    $self->assert(ref($site),
                  "Can't load Web object");
    $site->set_current;

    my %matrix=(
        t1 => {
            template => '<%URL%>',
            result => 'http://www.xao.com/WebURL.html',
        },
        t2 => {
            template => '<%URL active%>',
            result => 'http://www.xao.com/WebURL.html',
        },
        t3 => {
            template => '<%URL active top%>',
            result => 'http://www.xao.com',
        },
        t4 => {
            template => '<%URL active full%>',
            result => 'http://www.xao.com/WebURL.html',
        },
        t5 => {
            template => '<%URL active secure%>',
            result => 'https://www.xao.com/WebURL.html',
        },
        t6 => {
            template => '<%URL active top secure%>',
            result => 'https://www.xao.com',
        },
        t7 => {
            template => '<%URL active full secure%>',
            result => 'https://www.xao.com/WebURL.html',
        },
        t9 => {
            template => '<%URL base%>',
            result => 'http://xao.com/WebURL.html',
        },
        t9 => {
            template => '<%URL base top%>',
            result => 'http://xao.com',
        },
        ta => {
            template => '<%URL base full%>',
            result => 'http://xao.com/WebURL.html',
        },
        tb => {
            template => '<%URL base secure%>',
            result => 'https://xao.com/WebURL.html',
        },
        tc => {
            template => '<%URL base top secure%>',
            result => 'https://xao.com',
        },
        td => {
            template => '<%URL base full secure%>',
            result => 'https://xao.com/WebURL.html',
        },
        te => {
            template => '<%URL secure%>',
            result => 'https://www.xao.com/WebURL.html',
        },
    );

    foreach my $test (keys %matrix) {
        my $template=$matrix{$test}->{template};
        my $expect=$matrix{$test}->{result};

        my $got=$site->expand(
            cgi     => $cgi,
            path    => '/WebURL.html',
            objargs => {
                TEMPLATE    => $template,
            },
        );

        $self->assert($got eq $expect,
                      "Test $test failed - expected '$expect', got '$got'");
    }
}

###############################################################################
1;
