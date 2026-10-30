<?php

declare(strict_types=1);

use App\Tests\Behat\DemoContext;
use Behat\Config\Config;
use Behat\Config\Extension;
use Behat\Config\Profile;
use Behat\Config\Suite;
use FriendsOfBehat\SymfonyExtension\ServiceContainer\SymfonyExtension;

return (new Config())
    ->withProfile(
        (new Profile('default'))
            ->withSuite(
                (new Suite('default'))
                    ->withContexts(DemoContext::class),
            )
            // The php container exports APP_ENV=dev, which the extension would pick up otherwise
            ->withExtension(new Extension(SymfonyExtension::class, [
                'kernel' => ['environment' => 'test'],
            ])),
    );
