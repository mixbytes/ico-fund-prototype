'use strict';

// testrpc has to be run as testrpc -u 0 -u 1 -u 2 -u 3 -u 4 -u 5

import expectThrow from './helpers/expectThrow';

const DAOFund = artifacts.require("../test_helpers/DAOFundTestHelper.sol");
const SimpleTestDAOToken = artifacts.require("../test_helpers/SimpleTestDAOToken.sol");
const SimpleTestDAOVault = artifacts.require("../test_helpers/SimpleTestDAOVault.sol");


contract('DAOFund', function(accounts) {

    function getRoles() {
        return {
            deployer: accounts[0],
            team: accounts[1],
            investor1: accounts[2],
            investor2: accounts[3],
            investor3: accounts[4],
            nobody: accounts[5]
        };
    }

    function tokens(num) {
        return web3.toWei(num, 'ether');
    }

    const weeks = 86400*7;

    async function instantiate() {
        const role = getRoles();

        const vault = await SimpleTestDAOVault.new(role.team, {from: role.deployer});
        await vault.sendTransaction({from: role.deployer, value: web3.toWei(100, 'finney')});

        const token = await SimpleTestDAOToken.new({from: role.deployer});
        await token.mint(role.investor1, tokens(450));
        await token.mint(role.investor2, tokens(300));
        await token.mint(role.investor3, tokens(250));

        const fund = await DAOFund.new(vault.address, token.address, 1, {from: role.deployer});
        await vault.activate(fund.address, {from: role.deployer});
        await token.activate(fund.address, {from: role.deployer});
        await fund.init({from: role.deployer});

        return [fund, vault, token];
    }

    function assertBigNumberEqual(actual, expected, message=undefined) {
        assert(actual.eq(expected), (message ? message + ': ' : '') + "expected "+expected+", but got: "+actual);
    }

    async function assertVotes(fund, approvalExpected, disapprovalExpected) {
        const [actualApproval, actualDisapproval] = await fund.getVotes();
        assertBigNumberEqual(actualApproval, tokens(approvalExpected), 'approval votes check');
        assertBigNumberEqual(actualDisapproval, tokens(disapprovalExpected), 'disapproval votes check');
    }


    it("test instantiation", async function() {
        const role = getRoles();
        const teamInitialBalance = await web3.eth.getBalance(role.team);
        const [fund, vault, token] = await instantiate();
        // first tranche
        assertBigNumberEqual(await web3.eth.getBalance(role.team).sub(teamInitialBalance), web3.toWei(25, 'finney'));
        assert(await fund.isActive());
    });


    it("test simple voting", async function() {
        const role = getRoles();
        const [fund, vault, token] = await instantiate();

        // voting time
        await fund.setTime(3 * weeks);

        for (const from_ of [role.deployer, role.team, role.nobody])
            await expectThrow(fund.approveKeyPoint(true, {from: from_}));

        await fund.approveKeyPoint(false, {from: role.investor1});
        await expectThrow(fund.approveKeyPoint(true, {from: role.investor1}));
        await expectThrow(fund.approveKeyPoint(false, {from: role.investor1}));

        await fund.approveKeyPoint(true, {from: role.investor2});
        await fund.approveKeyPoint(true, {from: role.investor3});

        for (const from_ of [role.deployer, role.team, role.nobody])
            await expectThrow(fund.approveKeyPoint(true, {from: from_}));

        await expectThrow(fund.executeKeyPoint({from: role.nobody}));   // too early
        await expectThrow(fund.executeKeyPoint({from: role.investor2}));   // too early
        await expectThrow(fund.executeKeyPoint({from: role.team}));   // too early

        // executing time
        await fund.setTime(43 * weeks);
        const teamInitialBalance = await web3.eth.getBalance(role.team);
        await fund.executeKeyPoint({from: role.nobody});
        // second tranche
        assertBigNumberEqual(await web3.eth.getBalance(role.team).sub(teamInitialBalance), web3.toWei(45, 'finney'));

        assert(await fund.isActive());
    });


    it("test partial quorum voting", async function() {
        const role = getRoles();
        const [fund, vault, token] = await instantiate();

        // voting time
        await fund.setTime(3 * weeks);

        await fund.approveKeyPoint(true, {from: role.investor1});
        await fund.approveKeyPoint(true, {from: role.investor3});

        // executing time
        await fund.setTime(43 * weeks);
        await expectThrow(fund.approveKeyPoint(false, {from: role.investor2}));     // too late
        const teamInitialBalance = await web3.eth.getBalance(role.team);
        await fund.executeKeyPoint({from: role.nobody});
        // second tranche
        assertBigNumberEqual(await web3.eth.getBalance(role.team).sub(teamInitialBalance), web3.toWei(45, 'finney'));

        assert(await fund.isActive());
    });


    it("test voting with token transfer", async function() {
        const role = getRoles();
        const [fund, vault, token] = await instantiate();

        // voting time
        await fund.setTime(3 * weeks);

        await fund.approveKeyPoint(true, {from: role.investor1});
        await fund.approveKeyPoint(false, {from: role.investor2});
        await fund.approveKeyPoint(false, {from: role.investor3});
        await token.transfer(role.investor1, tokens(100), {from: role.investor2});

        // executing time
        await fund.setTime(43 * weeks);
        const teamInitialBalance = await web3.eth.getBalance(role.team);
        await fund.executeKeyPoint({from: role.nobody});
        assertBigNumberEqual(await web3.eth.getBalance(role.team).sub(teamInitialBalance), web3.toWei(45, 'finney'));

        assert(await fund.isActive());
    });


    it("test project success", async function() {
        const role = getRoles();
        const teamInitialBalance = await web3.eth.getBalance(role.team);
        const [fund, vault, token] = await instantiate();

        // 2nd key point
        await fund.setTime(3 * weeks);
        await expectThrow(fund.refund({from: role.investor1}));
        await fund.approveKeyPoint(false, {from: role.investor1});
        await expectThrow(fund.refund({from: role.investor1}));
        await fund.approveKeyPoint(true, {from: role.investor2});
        await fund.approveKeyPoint(true, {from: role.investor3});
        await fund.setTime(43 * weeks);
        await expectThrow(fund.refund({from: role.investor1}));
        await fund.executeKeyPoint({from: role.nobody});
        await expectThrow(fund.refund({from: role.investor1}));

        // 3rd key point
        await fund.setTime(44 * weeks);
        await expectThrow(fund.refund({from: role.investor1}));
        await fund.approveKeyPoint(false, {from: role.investor1});
        await expectThrow(fund.refund({from: role.investor1}));
        await fund.approveKeyPoint(true, {from: role.investor2});
        await fund.approveKeyPoint(true, {from: role.investor3});
        await fund.setTime(64 * weeks);
        await expectThrow(fund.refund({from: role.investor1}));
        await fund.executeKeyPoint({from: role.nobody});
        await expectThrow(fund.refund({from: role.investor1}));

        assertBigNumberEqual(await web3.eth.getBalance(role.team).sub(teamInitialBalance), web3.toWei(100, 'finney'));

        assert(await fund.isFinished());
    });


    it("test project failure", async function() {
        const role = getRoles();
        const teamInitialBalance = await web3.eth.getBalance(role.team);
        const [fund, vault, token] = await instantiate();

        // 2nd key point
        await fund.setTime(3 * weeks);
        await fund.approveKeyPoint(false, {from: role.investor1});
        await fund.approveKeyPoint(true, {from: role.investor2});
        await fund.approveKeyPoint(true, {from: role.investor3});
        await fund.setTime(43 * weeks);
        await fund.executeKeyPoint({from: role.nobody});

        // 3rd key point
        await fund.setTime(44 * weeks);
        await fund.approveKeyPoint(false, {from: role.investor2});
        await fund.approveKeyPoint(false, {from: role.investor1});
        await fund.setTime(64 * weeks);
        await fund.executeKeyPoint({from: role.nobody});

        assertBigNumberEqual(await web3.eth.getBalance(role.team).sub(teamInitialBalance), web3.toWei(70, 'finney'));

        let initial = await web3.eth.getBalance(role.investor1);
        await fund.refund({from: role.investor1, gasPrice: 0});
        assertBigNumberEqual(await token.balanceOf(role.investor1), 0);
        assertBigNumberEqual(await web3.eth.getBalance(role.investor1).sub(initial), web3.toWei(30*450/1000, 'finney'));
        await expectThrow(fund.refund({from: role.investor1}));

        initial = await web3.eth.getBalance(role.investor2);
        await fund.refund({from: role.investor2, gasPrice: 0});
        assertBigNumberEqual(await token.balanceOf(role.investor2), 0);
        assertBigNumberEqual(await web3.eth.getBalance(role.investor2).sub(initial), web3.toWei(30*300/1000, 'finney'));
        await expectThrow(fund.refund({from: role.investor2}));

        initial = await web3.eth.getBalance(role.investor3);
        await fund.refund({from: role.investor3, gasPrice: 0});
        assertBigNumberEqual(await token.balanceOf(role.investor3), 0);
        assertBigNumberEqual(await web3.eth.getBalance(role.investor3).sub(initial), web3.toWei(30*250/1000, 'finney'));
        await expectThrow(fund.refund({from: role.investor3}));

        assert(await fund.isRefunding());
    });


    it("test delegation chain voting", async function() {
        const role = getRoles();

        let [fund, vault, token] = await instantiate();
        await fund.setTime(3 * weeks);

        await fund.delegate(role.investor1, {from: role.investor2});
        await fund.delegate(role.investor2, {from: role.investor3});
        await fund.approveKeyPoint(true, {from: role.investor1});
        await assertVotes(fund, 1000, 0);


        [fund, vault, token] = await instantiate();
        await fund.setTime(3 * weeks);

        await fund.delegate(role.investor2, {from: role.investor3});
        await fund.delegate(role.investor1, {from: role.investor2});
        await fund.approveKeyPoint(true, {from: role.investor1});
        await assertVotes(fund, 1000, 0);


        [fund, vault, token] = await instantiate();
        await fund.setTime(3 * weeks);

        await fund.delegate(role.investor1, {from: role.investor2});
        await fund.delegate(role.investor1, {from: role.investor3});
        await fund.approveKeyPoint(true, {from: role.investor1});
        await assertVotes(fund, 1000, 0);
    });


    it("test non-voted delegate voting", async function() {
        const role = getRoles();
        const [fund, vault, token] = await instantiate();
        await fund.setTime(3 * weeks);

        await fund.delegate(role.investor1, {from: role.investor2});
        await fund.approveKeyPoint(true, {from: role.investor1});
        await fund.approveKeyPoint(false, {from: role.investor3});
        await assertVotes(fund, 750, 250);
    });


    it("test voted delegate voting", async function() {
        const role = getRoles();
        const [fund, vault, token] = await instantiate();
        await fund.setTime(3 * weeks);

        await fund.delegate(role.investor1, {from: role.investor2});
        await fund.approveKeyPoint(true, {from: role.investor1});
        await expectThrow(fund.approveKeyPoint(true, {from: role.investor1}));
    });


    it("test non-voted delegate token transfer", async function() {
        const role = getRoles();
        const [fund, vault, token] = await instantiate();
        await fund.setTime(3 * weeks);

        await fund.delegate(role.investor1, {from: role.investor2});
        await token.transfer(role.investor1, tokens(100), {from: role.investor3});
        await assertVotes(fund, 0, 0);
        await fund.approveKeyPoint(true, {from: role.investor1});
        await fund.approveKeyPoint(false, {from: role.investor3});
        await assertVotes(fund, 850, 150);
    });


    it("test voted delegate token transfer", async function() {
        const role = getRoles();
        const [fund, vault, token] = await instantiate();
        await fund.setTime(3 * weeks);

        await fund.delegate(role.investor1, {from: role.investor2});
        await fund.approveKeyPoint(true, {from: role.investor1});
        await fund.approveKeyPoint(false, {from: role.investor3});
        await assertVotes(fund, 750, 250);
        await token.transfer(role.investor1, tokens(150), {from: role.investor3});
        await assertVotes(fund, 900, 100);
    });


    it("test delegator (to non-voted delegate) voting", async function() {
        const role = getRoles();
        const [fund, vault, token] = await instantiate();
        await fund.setTime(3 * weeks);

        await fund.delegate(role.investor1, {from: role.investor2});
        await expectThrow(fund.approveKeyPoint(true, {from: role.investor2}));
        await fund.approveKeyPoint(true, {from: role.investor1});
        await fund.approveKeyPoint(false, {from: role.investor3});
        await assertVotes(fund, 750, 250);
    });


    it("test delegator (to voted delegate) voting", async function() {
        const role = getRoles();
        const [fund, vault, token] = await instantiate();
        await fund.setTime(3 * weeks);

        await fund.delegate(role.investor1, {from: role.investor2});
        await fund.approveKeyPoint(true, {from: role.investor1});
        await expectThrow(fund.approveKeyPoint(true, {from: role.investor2}));
    });


    it("test delegator (to non-voted delegate) token transfer", async function() {
        const role = getRoles();
        const [fund, vault, token] = await instantiate();
        await fund.setTime(3 * weeks);

        await fund.delegate(role.investor1, {from: role.investor2});
        await token.transfer(role.investor2, tokens(100), {from: role.investor3});
        await assertVotes(fund, 0, 0);
        await fund.approveKeyPoint(true, {from: role.investor1});
        await fund.approveKeyPoint(false, {from: role.investor3});
        await assertVotes(fund, 850, 150);
    });


    it("test delegator (to voted delegate) token transfer", async function() {
        const role = getRoles();
        const [fund, vault, token] = await instantiate();
        await fund.setTime(3 * weeks);

        await fund.delegate(role.investor1, {from: role.investor2});
        await fund.approveKeyPoint(true, {from: role.investor1});
        await fund.approveKeyPoint(false, {from: role.investor3});
        await assertVotes(fund, 750, 250);
        await token.transfer(role.investor2, tokens(150), {from: role.investor3});
        await assertVotes(fund, 900, 100);
    });
});
