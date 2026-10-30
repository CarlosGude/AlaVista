<?php

namespace App\Security;

use App\Entity\User;
use App\Repository\UserRepository;
use Doctrine\ORM\EntityManagerInterface;
use KnpU\OAuth2ClientBundle\Client\OAuth2ClientInterface;
use KnpU\OAuth2ClientBundle\Security\Authenticator\OAuth2Authenticator;
use League\OAuth2\Client\Provider\GoogleUser;
use Symfony\Component\DependencyInjection\Attribute\Autowire;
use Symfony\Component\HttpFoundation\RedirectResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Generator\UrlGeneratorInterface;
use Symfony\Component\Security\Core\Authentication\Token\TokenInterface;
use Symfony\Component\Security\Core\Exception\AuthenticationException;
use Symfony\Component\Security\Core\Exception\CustomUserMessageAuthenticationException;
use Symfony\Component\Security\Http\Authenticator\Passport\Badge\UserBadge;
use Symfony\Component\Security\Http\Authenticator\Passport\Passport;
use Symfony\Component\Security\Http\Authenticator\Passport\SelfValidatingPassport;
use Symfony\Component\Security\Http\EntryPoint\AuthenticationEntryPointInterface;

/**
 * Signs in with Google. Only verified accounts listed in ADMIN_EMAILS are accepted,
 * and they are stored as users with ROLE_ADMIN.
 */
class GoogleAuthenticator extends OAuth2Authenticator implements AuthenticationEntryPointInterface
{
    /**
     * @var list<string>
     */
    private readonly array $adminEmails;

    /**
     * @param list<string> $adminEmails
     */
    public function __construct(
        #[Autowire(service: 'knpu.oauth2.client.google')]
        private readonly OAuth2ClientInterface $googleClient,
        private readonly UserRepository $userRepository,
        private readonly EntityManagerInterface $entityManager,
        private readonly UrlGeneratorInterface $urlGenerator,
        #[Autowire(env: 'csv:ADMIN_EMAILS')]
        array $adminEmails,
    ) {
        $this->adminEmails = array_map(static fn (string $email): string => mb_strtolower(trim($email)), $adminEmails);
    }

    public function supports(Request $request): ?bool
    {
        return 'connect_google_check' === $request->attributes->get('_route');
    }

    public function authenticate(Request $request): Passport
    {
        $accessToken = $this->fetchAccessToken($this->googleClient);

        return new SelfValidatingPassport(new UserBadge($accessToken->getToken(), function () use ($accessToken): User {
            /** @var GoogleUser $googleUser */
            $googleUser = $this->googleClient->fetchUserFromToken($accessToken);
            $email = mb_strtolower((string) $googleUser->getEmail());

            if ('' === $email || true !== $googleUser->getEmailVerified()) {
                throw new CustomUserMessageAuthenticationException('The email address of this Google account is not verified.');
            }

            if (!\in_array($email, $this->adminEmails, true)) {
                throw new CustomUserMessageAuthenticationException('This Google account is not allowed to sign in.');
            }

            $user = $this->userRepository->findOneBy(['googleId' => (string) $googleUser->getId()])
                ?? $this->userRepository->findOneBy(['email' => $email])
                ?? new User();

            $user
                ->setGoogleId((string) $googleUser->getId())
                ->setEmail($email)
                ->setName($googleUser->getName())
                ->setRoles(['ROLE_ADMIN']);

            $this->entityManager->persist($user);
            $this->entityManager->flush();

            return $user;
        }));
    }

    public function onAuthenticationSuccess(Request $request, TokenInterface $token, string $firewallName): ?Response
    {
        return new RedirectResponse($this->getPreviousUrl($request, $firewallName) ?? $this->urlGenerator->generate('admin'));
    }

    public function onAuthenticationFailure(Request $request, AuthenticationException $exception): ?Response
    {
        $this->saveAuthenticationErrorToSession($request, $exception);

        return new RedirectResponse($this->urlGenerator->generate('app_login'));
    }

    /**
     * Sends anonymous users hitting a protected page (e.g. /admin) to the login page.
     */
    public function start(Request $request, ?AuthenticationException $authException = null): Response
    {
        return new RedirectResponse($this->urlGenerator->generate('app_login'));
    }
}
