<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
    <head>
        <meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/>
        <title><?php echo $title ?></title>
        <link href="/main.css" type="text/css" rel="stylesheet" />
        <link href="/img/devcamps-favicon.png" type="image/png" rel="shortcut icon" />
    </head>
    <body<?php
    if ($page_type == 'doc') echo ' id="body" class="doc"';
?>>
        <div id="header" class="fix">
            <div class="wrapper">
                <a id="logo" href="/"><img src="/img/devcamps.png" alt="home"/></a>
                <ul id="menu-main">
                    <li><a href="/why">why camps?</a></li>
                    <li><a href="/documentation">documentation</a></li>
                    <li><a href="/community">community</a></li>
                    <li><a href="/code">code</a></li>
                </ul>
            </div>
        </div>

        <div id="intro" class="fix">
            <div class="inner">
                <div class="wrapper">
