import { Foundry } from "@adraffy/blocksmith";
import { namehash, solidityPackedKeccak256 } from "ethers";
import { test } from "node:test";
import assert from "node:assert/strict";
import { ENS_REGISTRY, BASE_VERIFIER, TEAM_NICK_NFT } from "./config.js";

test("TeamNick", async (T) => {
	const foundry = await Foundry.launch({
		fork: "https://rpc.ankr.com/eth",
		infoLog: false,
	});
	T.after(foundry.shutdown);

	const TeamNickResolver = await foundry.deploy({
		file: "TeamNickResolver",
		args: [ENS_REGISTRY, BASE_VERIFIER],
	});

	const BASENAME = "teamnick.eth";

	// replace resolver in registry
	await foundry.setStorageValue(
		ENS_REGISTRY,
		BigInt(
			solidityPackedKeccak256(
				["bytes32", "uint256"],
				[namehash(BASENAME), 0n]
			)
		) + 1n,
		TeamNickResolver.target
	);

	async function testLabel(label, { address = null, avatar = null } = {}) {
		const name = `${label}.${BASENAME}`;
		await T.test(name, async (TT) => {
			const resolver = await foundry.provider.getResolver(name);
			assert(resolver, "expected resolver");
			await TT.test("addr()", async () => {
				assert.equal(await resolver.getAddress(), address);
			});
			await TT.test("text(avatar)", async () => {
				assert.equal(await resolver.getAvatar(), avatar);
			});
		});
	}
	await testLabel("__dne");
	await testLabel("raffy", {
		address: "0x51050ec063d393217B436747617aD1C2285Aeeee",
		avatar: "https://raffy.antistupid.com/ens.jpg",
	});
	await testLabel("slobo", {
		address: "0x534631Bcf33BDb069fB20A93d2fdb9e4D4dD42CF",
		avatar: "https://cdn.pixabay.com/photo/2012/05/04/10/17/sun-47083_1280.png",
	});

	await T.test(BASENAME, async (TT) => {
		const resolver = await foundry.provider.getResolver(BASENAME);
		assert(resolver, "expected resolver");
		await TT.test("addr()", async () => {
			assert.equal(
				await resolver.getAddress(),
				foundry.wallets.admin.address
			);
		});
		await TT.test("addr(base)", async () => {
			assert.equal(await resolver.getAddress(8453), TEAM_NICK_NFT);
		});
		await TT.test("text(description)", async () => {
			assert.match(
				await resolver.getText("description"),
				/^\d+ names registered$/
			);
		});
		await TT.test("text(url)", async () => {
			assert.equal(await resolver.getText("url"), "https://teamnick.xyz");
		});
		await TT.test("text(url) after change", async () => {
			const url = "https://chonk.com";
			await foundry.confirm(TeamNickResolver.setURL(url));
			assert.equal(await resolver.getText("url"), url);
		});
	});
});
