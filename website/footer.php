                </div>
            </div>
        </div>

        <div id="footer" class="fix">
            <div class="inner">
                <div class="wrapper">
<?php

$page = $_SERVER['REQUEST_URI'];

if (preg_match('/\/why$/', $page)) {
    $quote = <<<END
<p>“The DevCamps system has provided a fantastic platform for making changes to our website with the ability to proof them in a safe environment, away from the public eye. The camps environment also allows us to keep lots of projects rolling at one time. Camps are an invaluable part of the daily development of our website.”</p>

<p class="attribution">—Karen Jacob, Director of Web Development, <a href="https://www.citypass.com/">CityPASS</a></p>
END;
}
else if (preg_match('/\/documentation$/', $page)) {
    $quote = <<<END
<p>“We’ve been using DevCamps for almost two years, and have been able to roll out more projects during this timeframe than in our entire 10 year history. Camps makes it easy to have multiple developers working on multiple projects simultaneously, allowing for our software development goals to be reached in as little time as possible.”</p>

<p class="attribution">—Arshil Abdulla, Owner, <a href="https://www.lensdiscounters.com/">LensDiscounters.com</a></p>
END;
}
else if (preg_match('/\/community$/', $page)) {
    $quote = <<<END
<p>“Paper Source has been using Camps for 3 years. With Camps, developers and content managers can work on multiple projects simultaneously, each in their own staging environment. I can have a new developer work on his or her own copy of the website without worrying about what might break. I can then see exactly what is new or has changed, merge a portion or all of the updates, test again and then move live. Camps foster productivity and peace of mind.”</p>

<p class="attribution">—Leigh Wetzel, Director, E-Commerce, <a href="https://www.papersource.com/">Paper Source</a></p>
END;
}
else if (preg_match('/\/code$/', $page)) {
    $quote = <<<END
<p>“Camps is honestly the best thing that has happened to my development.”</p>

<p class="attribution">—Sam Batschelet, Co-Owner, <a href="https://www.westbranchresort.com/">West Branch Angler &amp; Resort</a></p>
END;
}
else if (preg_match('/\/$/', $page)) {
    $quote = <<<END
<p>“There are real benefits to the Camp system that Backcountry couldn’t live without. Our developers, QA, and business owners work together on projects right from the beginning in a camp, which makes them all more productive. We can have many projects going at once using different camps. Developers manage their own camps with all the self-service tools they need. It really is a better way to work.</p>

<p class="attribution">—Spencer Christensen, Infrastructure Team Lead, <a href="https://www.backcountry.com/">Backcountry</a></p>
END;
}
else {
    $quote = <<<END
<p>DevCamps make website development projects easier!</p>
END;
}

echo $quote;
?>
                </div>
            </div>

        </div>

        <p id="copy">© 2006–<?php echo date("Y") ?> <a href="https://www.endpointdev.com/">End Point Corporation</a></p>

        <script async src="https://www.googletagmanager.com/gtag/js?id=G-EEF5LR6B99"></script>
        <script>
            window.dataLayer = window.dataLayer || [];
            function gtag(){dataLayer.push(arguments);}
            gtag('js', new Date());

            gtag('config', 'G-EEF5LR6B99');
        </script>
    </body>
</html>
