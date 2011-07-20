<?php
    $title = "Camps endorsements | DevCamps";
    include('header.php');
?>

<h1>Camps endorsements</h1>

<div class="mixcase">

<p>I was a little skeptical when Jon Jensen at <a href="http://www.endpoint.com/">End Point</a> wanted to set up DevCamps for our Web 2.0 initiative for our consumer e-commerce site. I mean, we were on a Linux virtual machine – and not that beefy of a VM at that. However, it did not take long to realize the benefits it provided. I was impressed with the performance even with a couple of dozen camps running! Creating or deleting camps is done with one command – can’t get much easier than that. If a particular development branch was put on hold, that camp could be turned off and restarted when it picked up again. Great tool!</p>

<p class="attribution">—John Kinder, IT Administrator, <a href="http://www.flor.com/">Interface Inc.</a></p>

<hr class="small" />

<p>A few years back, I joined an online retailer as CTO. When I got there, the dev team was 6-7 guys working on a single development/staging server, with sporadic updates between their desktop machines and the server. Pushes out to the production environment were done on an ad hoc basis.</p>

<p>The company was growing rapidly, so I had an open ticket to hire developers as quickly as I could find qualified ones (qualified in terms of both technological skill and coolness factors). Over the next couple of years, we built out the team to over 30 developers. Obviously, random code check-ins and production pushes couldn’t be done “when we feel like it”. We needed a system. We needed some control. We needed an expectation of quality checking and a regular schedule.</p>

<p>With the great help of <a href="http://www.endpoint.com/">End Point</a>, we developed “camps” (it is an outdoor retailer, so servers were named after mountains, or ski resorts, etc.) which was essentially an image of the current production environment. Each developer could have his/her camp, and do what they wanted with it. They could have more than one camp going, if they were working on multiple problems. They could share their camp with others for collaboration.</p>

<p>When it came time to push code, camps would by synched back in to the main camp, checked by QA, and then pushed out to production. I realize this all seems common sense to you as you read this – but that’s the point: it is common sense. There are more nuances than you think here. I invite you to explore, develop, and enjoy your new camp.</p>

<p class="attribution">—Dave Jenkins, Former CTO, <a href="http://www.backcountry.com/">Backcountry.com</a></p>

<p class="bottomspace" />

</div>

<?php
    include('footer.php');
?>
