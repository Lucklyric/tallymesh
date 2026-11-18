package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"math/big"
	"os"
	"sort"
	"strings"
	"time"

	"github.com/consensys/gnark-crypto/ecc"
	native "github.com/consensys/gnark-crypto/ecc/bn254/fr/poseidon2"
	"github.com/consensys/gnark/backend/groth16"
	"github.com/consensys/gnark/frontend"
	"github.com/consensys/gnark/frontend/cs/r1cs"
	"github.com/consensys/gnark/std/permutation/poseidon2"
)

var sizes = []int{16, 64, 100, 256, 1024}

const proveRuns = 5

// The receipt count is len(Amounts). gnark fixes it when the circuit is compiled.
type statement struct {
	Root, Session, Provider, Start, Total frontend.Variable `gnark:",public"`
	Amounts                               []frontend.Variable
	Payloads                              []frontend.Variable
}

func empty(count int) *statement {
	return &statement{Amounts: make([]frontend.Variable, count), Payloads: make([]frontend.Variable, count)}
}

func padded(count int) int {
	width := 1
	for width < count {
		width *= 2
	}
	return width
}

func (batch *statement) Define(api frontend.API) error {
	hash, err := poseidon2.NewPoseidon2FromParameters(api, 2, 6, 50)
	if err != nil {
		return err
	}
	count := len(batch.Amounts)
	api.ToBinary(api.Add(batch.Start, count-1), 64)
	api.ToBinary(batch.Start, 64)
	leaves := make([]frontend.Variable, padded(count))
	var total frontend.Variable = 0
	for index := range leaves {
		leaves[index] = 0
		if index >= count {
			continue
		}
		amount := batch.Amounts[index]
		api.ToBinary(amount, 64)
		total = api.Add(total, amount)
		packed := api.Add(api.Mul(api.Add(batch.Start, index), new(big.Int).Lsh(big.NewInt(1), 64)), amount)
		leaves[index] = hash.Compress(packed, batch.Payloads[index])
	}
	for width := len(leaves); width > 1; width /= 2 {
		for index := 0; index < width/2; index++ {
			leaves[index] = hash.Compress(leaves[2*index], leaves[2*index+1])
		}
	}
	api.AssertIsEqual(total, batch.Total)
	api.AssertIsEqual(batch.Root, hash.Compress(hash.Compress(batch.Session, batch.Provider), leaves[0]))
	return nil
}

// fixture builds count receipts with sequence numbers start, start+1, ...
// Amounts alternate 10 and 110 by absolute sequence, so every batch of even size totals 60 per receipt.
func fixture(count, start int) statement {
	permutation := native.NewPermutation(2, 6, 50)
	hash := func(left, right *big.Int) *big.Int {
		out, err := permutation.Compress(left.FillBytes(make([]byte, 32)), right.FillBytes(make([]byte, 32)))
		if err != nil {
			panic(err)
		}
		return new(big.Int).SetBytes(out)
	}
	batch := *empty(count)
	batch.Session, batch.Provider, batch.Start = 11, 22, start
	leaves := make([]*big.Int, padded(count))
	total := 0
	for index := range leaves {
		leaves[index] = new(big.Int)
		if index >= count {
			continue
		}
		sequence := start + index
		amount := 10 + (sequence-1)%2*100
		total += amount
		payload := big.NewInt(int64(sequence + 900))
		batch.Amounts[index], batch.Payloads[index] = amount, payload
		packed := new(big.Int).Lsh(big.NewInt(int64(sequence)), 64)
		leaves[index] = hash(packed.Add(packed, big.NewInt(int64(amount))), payload)
	}
	for width := len(leaves); width > 1; width /= 2 {
		for index := 0; index < width/2; index++ {
			leaves[index] = hash(leaves[2*index], leaves[2*index+1])
		}
	}
	batch.Total = total
	batch.Root = hash(hash(big.NewInt(11), big.NewInt(22)), leaves[0])
	return batch
}

type reservation struct {
	root                             *big.Int
	session, provider, next, balance int
	final                            bool
}

func (escrow *reservation) claim(proof groth16.Proof, key groth16.VerifyingKey, batch statement) bool {
	if !escrow.final || escrow.root.Cmp(batch.Root.(*big.Int)) != 0 || batch.Session != escrow.session ||
		batch.Provider != escrow.provider || batch.Start != escrow.next || batch.Total.(int) > escrow.balance {
		return false
	}
	public, err := frontend.NewWitness(&batch, ecc.BN254.ScalarField(), frontend.PublicOnly())
	if err != nil || groth16.Verify(proof, key, public) != nil {
		return false
	}
	escrow.balance -= batch.Total.(int)
	escrow.next += len(batch.Amounts)
	return true
}

type result struct {
	Receipts        int       `json:"receipts"`
	PaddedLeaves    int       `json:"padded_leaves"`
	Constraints     int       `json:"constraints"`
	SetupMs         float64   `json:"setup_ms_single_sample"`
	ProveMsSamples  []float64 `json:"prove_ms_samples"`
	ProveMsMedian   float64   `json:"prove_ms_median"`
	ProveMsMin      float64   `json:"prove_ms_min"`
	ProveMsMax      float64   `json:"prove_ms_max"`
	VerifyMsSamples []float64 `json:"native_verify_ms_samples"`
	VerifyMsMedian  float64   `json:"native_verify_ms_median"`
	TotalUnits      int       `json:"batch_total_minor_units"`
}

func ms(elapsed time.Duration) float64 { return float64(elapsed.Microseconds()) / 1000 }

func median(samples []float64) (mid, low, high float64) {
	sorted := append([]float64(nil), samples...)
	sort.Float64s(sorted)
	return sorted[len(sorted)/2], sorted[0], sorted[len(sorted)-1]
}

func words(out *bytes.Buffer, name string, proof groth16.Proof) {
	encoded := proof.(interface{ MarshalSolidity() []byte }).MarshalSolidity()
	fmt.Fprintf(out, "function %s() internal pure returns(uint256[8] memory words) {\n", name)
	for i := 0; i < 8; i++ {
		fmt.Fprintf(out, "words[%d] = 0x%x;\n", i, encoded[32*i:32*i+32])
	}
	fmt.Fprintln(out, "}")
}

func run(count int) result {
	field := ecc.BN254.ScalarField()
	system, err := frontend.Compile(field, r1cs.NewBuilder, empty(count))
	must(err)
	start := time.Now()
	pk, vk, err := groth16.Setup(system)
	must(err)
	out := result{Receipts: count, PaddedLeaves: padded(count), Constraints: system.GetNbConstraints(), SetupMs: ms(time.Since(start))}
	batch := fixture(count, 1)
	out.TotalUnits = batch.Total.(int)
	full, err := frontend.NewWitness(&batch, field)
	must(err)
	pub, err := full.Public()
	must(err)
	var proof groth16.Proof
	for i := 0; i < proveRuns; i++ {
		start = time.Now()
		proof, err = groth16.Prove(system, pk, full)
		must(err)
		out.ProveMsSamples = append(out.ProveMsSamples, ms(time.Since(start)))
		start = time.Now()
		must(groth16.Verify(proof, vk, pub))
		out.VerifyMsSamples = append(out.VerifyMsSamples, ms(time.Since(start)))
	}
	out.ProveMsMedian, out.ProveMsMin, out.ProveMsMax = median(out.ProveMsSamples)
	out.VerifyMsMedian, _, _ = median(out.VerifyMsSamples)

	// Second consecutive batch (sequences count+1 .. 2*count) under the same keys, for the EVM tests. Not timed.
	second := fixture(count, count+1)
	secondWitness, err := frontend.NewWitness(&second, field)
	must(err)
	secondProof, err := groth16.Prove(system, pk, secondWitness)
	must(err)

	must(os.MkdirAll("generated", 0755))
	var verifier bytes.Buffer
	must(vk.ExportSolidity(&verifier))
	renamed := strings.Replace(verifier.String(), "contract Verifier {", fmt.Sprintf("contract Verifier%d {", count), 1)
	if renamed == verifier.String() {
		panic("verifier contract name not found")
	}
	must(os.WriteFile(fmt.Sprintf("generated/Verifier%d.sol", count), []byte(renamed), 0644))
	var code bytes.Buffer
	fmt.Fprintf(&code, "pragma solidity ^0.8.20; library Fixture%d {\n", count)
	fmt.Fprintf(&code, "uint256 internal constant ROOT = %s;\n", batch.Root)
	fmt.Fprintf(&code, "uint256 internal constant TOTAL = %d;\n", batch.Total)
	fmt.Fprintf(&code, "uint256 internal constant ROOT2 = %s;\n", second.Root)
	fmt.Fprintf(&code, "uint256 internal constant TOTAL2 = %d;\n", second.Total)
	words(&code, "proof", proof)
	words(&code, "proof2", secondProof)
	fmt.Fprintln(&code, "}")
	must(os.WriteFile(fmt.Sprintf("generated/Fixture%d.sol", count), code.Bytes(), 0644))

	var compressed, raw bytes.Buffer
	_, err = proof.WriteTo(&compressed)
	must(err)
	_, err = proof.WriteRawTo(&raw)
	must(err)
	fmt.Printf("receipts=%d paddedLeaves=%d constraints=%d setup=%.1fms prove(median/min/max of %d)=%.1f/%.1f/%.1fms verify(median)=%.3fms publicInputs=5 gnarkCompressed=%d gnarkRaw=%d\n",
		count, out.PaddedLeaves, out.Constraints, out.SetupMs, proveRuns, out.ProveMsMedian, out.ProveMsMin, out.ProveMsMax, out.VerifyMsMedian, compressed.Len(), raw.Len())

	total := batch.Total.(int)
	for _, mode := range []string{"optimistic", "validity"} {
		escrow := reservation{root: batch.Root.(*big.Int), session: 11, provider: 22, next: 1, balance: total + 4000}
		check := func(name string, got, want bool) {
			if got != want {
				panic(name)
			}
		}
		check("pending", escrow.claim(proof, vk, batch), false)
		escrow.final = true
		wrong := batch
		wrong.Total = total + 1
		check("inflation", escrow.claim(proof, vk, wrong), false)
		wrong = batch
		wrong.Provider = 23
		check("wrong recipient", escrow.claim(proof, vk, wrong), false)
		escrow.balance = total - 1
		check("overdraft", escrow.claim(proof, vk, batch), false)
		escrow.balance = total + 4000
		check("payout", escrow.claim(proof, vk, batch), true)
		check("replay", escrow.claim(proof, vk, batch), false)
		fmt.Printf("  %s finality fixture: paid=%d remaining=%d next=%d\n", mode, total, escrow.balance, escrow.next)
	}
	changed := batch
	changed.Amounts = append([]frontend.Variable(nil), batch.Amounts...)
	changed.Amounts[0] = 11
	changed.Amounts[1] = 109
	wrongWitness, err := frontend.NewWitness(&changed, field)
	must(err)
	if system.IsSolved(wrongWitness) == nil {
		panic("same-total substituted receipts accepted")
	}
	fmt.Println("  PASS: same-total substitution rejected by root constraint")
	return out
}

func main() {
	var results []result
	for _, count := range sizes {
		results = append(results, run(count))
	}
	encoded, err := json.MarshalIndent(results, "", "  ")
	must(err)
	must(os.MkdirAll("evidence", 0755))
	must(os.WriteFile("evidence/go-sweep.json", append(encoded, '\n'), 0644))
}

func must(err error) {
	if err != nil {
		panic(err)
	}
}
