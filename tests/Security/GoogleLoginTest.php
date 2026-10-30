<?php

namespace App\Tests\Security;

use App\Entity\User;
use App\Repository\UserRepository;
use Doctrine\ORM\EntityManagerInterface;
use KnpU\OAuth2ClientBundle\Client\OAuth2ClientInterface;
use League\OAuth2\Client\Provider\GoogleUser;
use League\OAuth2\Client\Token\AccessToken;
use PHPUnit\Framework\Attributes\DataProvider;
use Symfony\Bundle\FrameworkBundle\KernelBrowser;
use Symfony\Bundle\FrameworkBundle\Test\WebTestCase;

class GoogleLoginTest extends WebTestCase
{
    private KernelBrowser $client;

    protected function setUp(): void
    {
        $this->client = static::createClient();

        static::getContainer()->get(EntityManagerInterface::class)
            ->createQuery('DELETE FROM '.User::class)
            ->execute();
    }

    public function testAdminRedirectsAnonymousUsersToLogin(): void
    {
        $this->client->request('GET', '/admin');

        self::assertResponseRedirects('/login');
    }

    public function testLoginPageLinksToGoogle(): void
    {
        $this->client->request('GET', '/login');

        self::assertResponseIsSuccessful();
        self::assertSelectorExists('a[href="/connect/google"]');
    }

    public function testConnectRedirectsToGoogle(): void
    {
        $this->client->request('GET', '/connect/google');

        self::assertResponseStatusCodeSame(302);
        $location = (string) $this->client->getResponse()->headers->get('Location');
        self::assertStringStartsWith('https://accounts.google.com/o/oauth2/v2/auth?', $location);
        self::assertStringContainsString('client_id=test-client-id', $location);
        self::assertStringContainsString('redirect_uri='.urlencode('http://localhost/connect/google/check'), $location);
    }

    public function testAllowedAccountSignsInAndReachesAdmin(): void
    {
        $this->stubGoogleUser(['sub' => 'google-123', 'email' => 'Admin@Example.com', 'email_verified' => true, 'name' => 'Ada Lovelace']);

        $this->client->request('GET', '/connect/google/check?code=fake-code&state=fake-state');
        self::assertResponseRedirects('/admin');

        $this->client->followRedirect();
        self::assertResponseIsSuccessful();
        self::assertSelectorTextContains('body', 'Ada Lovelace');

        $user = static::getContainer()->get(UserRepository::class)->findOneBy(['googleId' => 'google-123']);
        self::assertNotNull($user);
        self::assertSame('admin@example.com', $user->getEmail());
        self::assertContains('ROLE_ADMIN', $user->getRoles());
    }

    public function testAdminCanBrowseUsersAndSignOut(): void
    {
        $this->stubGoogleUser(['sub' => 'google-123', 'email' => 'admin@example.com', 'email_verified' => true, 'name' => 'Ada Lovelace']);
        $this->client->request('GET', '/connect/google/check?code=fake-code&state=fake-state');
        $user = static::getContainer()->get(UserRepository::class)->findOneBy(['email' => 'admin@example.com']);

        $this->client->request('GET', '/admin/user');
        self::assertResponseIsSuccessful();
        self::assertAnySelectorTextContains('table td', 'admin@example.com');

        $this->client->request('GET', '/admin/user/'.$user->getId());
        self::assertResponseIsSuccessful();
        self::assertSelectorTextContains('body', 'google-123');

        $this->client->request('GET', '/logout');
        self::assertResponseRedirects('/login');

        $this->client->request('GET', '/admin');
        self::assertResponseRedirects('/login');
    }

    /**
     * @param array<string, mixed> $googleUserData
     */
    #[DataProvider('rejectedAccountProvider')]
    public function testRejectedAccountCannotSignIn(array $googleUserData, string $expectedError): void
    {
        $this->stubGoogleUser($googleUserData);

        $this->client->request('GET', '/connect/google/check?code=fake-code&state=fake-state');
        self::assertResponseRedirects('/login');

        $this->client->followRedirect();
        self::assertSelectorTextContains('.alert-danger', $expectedError);
        self::assertSame(0, static::getContainer()->get(UserRepository::class)->count([]));
    }

    public static function rejectedAccountProvider(): iterable
    {
        yield 'email not in ADMIN_EMAILS' => [
            ['sub' => 'google-456', 'email' => 'someone@example.com', 'email_verified' => true, 'name' => 'Someone'],
            'This Google account is not allowed to sign in.',
        ];
        yield 'unverified email' => [
            ['sub' => 'google-789', 'email' => 'admin@example.com', 'email_verified' => false, 'name' => 'Impostor'],
            'The email address of this Google account is not verified.',
        ];
    }

    /**
     * Replaces the Google OAuth client so the callback succeeds without calling Google.
     *
     * @param array<string, mixed> $googleUserData
     */
    private function stubGoogleUser(array $googleUserData): void
    {
        $googleClient = $this->createStub(OAuth2ClientInterface::class);
        $googleClient->method('getAccessToken')->willReturn(new AccessToken(['access_token' => 'fake-token']));
        $googleClient->method('fetchUserFromToken')->willReturn(new GoogleUser($googleUserData));

        static::getContainer()->set('knpu.oauth2.client.google', $googleClient);
    }
}
