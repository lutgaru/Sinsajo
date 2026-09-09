// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// https://astro.build/config
export default defineConfig({
	site: 'https://lutgaru.github.io',
	base: '/Sinsajo/',
	integrations: [
		starlight({
			title: 'Sinsajo',
			description: 'Real-time local voice transcription — 100% offline, self-hosted Flutter + Rust',
			logo: {
				src: './src/assets/sinsajo.svg',
				alt: 'Sinsajo logo',
			},
			favicon: '/sinsajo.svg',
			customCss: ['./src/styles/custom.css'],
			social: [
				{ icon: 'github', label: 'GitHub', href: 'https://github.com/lutgaru/Sinsajo' },
				{ icon: 'discord', label: 'Docker Hub', href: 'https://hub.docker.com/r/lutgaru/sinsajo-server' },
			],
			editLink: {
				baseUrl: 'https://github.com/lutgaru/Sinsajo/edit/master/docs-site/',
			},
			head: [
				{ tag: 'meta', attrs: { property: 'og:image', content: 'https://lutgaru.github.io/Sinsajo/sinsajo.svg' } },
			],
			sidebar: [
				{
					label: 'Start Here',
					items: [
						{ label: 'Introduction', slug: 'intro' },
						{ label: 'Quick Start', slug: 'guides/quickstart' },
					],
				},
				{
					label: 'Guides',
					items: [
						{ label: 'Architecture', slug: 'guides/architecture' },
						{ label: 'Client (Flutter)', slug: 'guides/client' },
						{ label: 'Server (Rust)', slug: 'guides/server' },
						{ label: 'Configuration', slug: 'guides/configuration' },
						{ label: 'Protocol', slug: 'guides/protocol' },
					],
				},
				{
					label: 'Reference',
					items: [
						{ label: 'Troubleshooting', slug: 'reference/troubleshooting' },
						{ label: 'Performance', slug: 'reference/performance' },
						{ label: 'Roadmap', slug: 'reference/roadmap' },
					],
				},
			],
		}),
	],
});
