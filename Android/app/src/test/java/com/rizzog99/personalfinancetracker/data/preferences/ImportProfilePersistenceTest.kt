package com.rizzog99.personalfinancetracker.data.preferences

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.preferencesDataStoreFile
import androidx.test.core.app.ApplicationProvider
import com.rizzog99.personalfinancetracker.domain.import.CsvColumnMapping
import com.rizzog99.personalfinancetracker.domain.import.SignConvention
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Parity `M1-DATA-PREFS` (#118) for the import-profile settings named in AC-02, plus the same-key
 * concurrency contract AC-04 asks for: [ImportProfileRepository] is the one preference that stores
 * a whole collection under a single key, so it is the only place a lost update can happen.
 */
@RunWith(RobolectricTestRunner::class)
class ImportProfilePersistenceTest {

    private lateinit var context: Context
    private lateinit var file: File
    private var session: StoreSession? = null

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        file = context.preferencesDataStoreFile("m1_data_prefs_import_ac")
        file.delete()
    }

    @After
    fun tearDown() = runBlocking {
        session?.close()
        file.delete()
        Unit
    }

    @Test
    fun `AC-01 a clean store remembers no import profile and writes no placeholder`() = runBlocking {
        val store = openStore()
        val repository = ImportProfileRepository(store)

        assertEquals(emptyMap<String, ImportProfile>(), repository.profiles.first())
        assertNull(repository.profile(SIGNATURE))
        assertEquals(emptyMap<Preferences.Key<*>, Any>(), store.data.first().asMap())
    }

    @Test
    fun `AC-02 a saved import profile survives a full store restart with every field exact`() = runBlocking {
        val repository = ImportProfileRepository(openStore())
        val profile = ImportProfile(
            mapping = CsvColumnMapping(
                date = "Data operazione",
                amount = "Importo",
                category = "Categoria",
                note = "Descrizione operazione",
                type = "Tipo",
                dateFormat = "yyyy-MM-dd HH:mm:ss",
                signConvention = SignConvention.ALL_EXPENSES,
            ),
            categorySelections = mapOf(
                "Supermercato" to "7e1f2a60-0000-4000-8000-000000000001",
                "" to "7e1f2a60-0000-4000-8000-000000000002",
            ),
        )

        repository.save(profile, SIGNATURE)
        val reopened = ImportProfileRepository(restart())

        assertEquals(profile, reopened.profile(SIGNATURE))
        assertEquals(mapOf(SIGNATURE to profile), reopened.profiles.first())
    }

    @Test
    fun `AC-02 a minimal profile keeps its unmapped columns null rather than the string null`() = runBlocking {
        val repository = ImportProfileRepository(openStore())
        val profile = ImportProfile(mapping = CsvColumnMapping(date = "Date", amount = "Amount"))

        repository.save(profile, SIGNATURE)
        val reopened = requireNotNull(ImportProfileRepository(restart()).profile(SIGNATURE))

        assertEquals(profile, reopened)
        assertNull(reopened.mapping.category)
        assertNull(reopened.mapping.note)
        assertNull(reopened.mapping.type)
        assertEquals("dd/MM/yyyy", reopened.mapping.dateFormat)
        assertEquals(SignConvention.SIGNED, reopened.mapping.signConvention)
        assertEquals(emptyMap<String, String>(), reopened.categorySelections)
    }

    @Test
    fun `AC-03 the layout signature separates headers that would otherwise collide`() {
        val split = ImportProfileRepository.signature(listOf("a", "b"), ',')
        val joined = ImportProfileRepository.signature(listOf("a,b"), ',')
        val otherDelimiter = ImportProfileRepository.signature(listOf("a", "b"), ';')

        assertNotEquals(split, joined)
        assertNotEquals(split, otherDelimiter)
        assertEquals(split, ImportProfileRepository.signature(listOf("a", "b"), ','))
        assertEquals(64, split.length)

        // Golden vectors computed outside this code from iOS's payload recipe — headers joined by
        // U+001F, then U+001E, then the delimiter, SHA-256 over the UTF-8 bytes. Pins the payload
        // construction so a refactor cannot silently change what a layout hashes to.
        assertEquals("47d552efb09fc23eb540c4ac0e9e28955d596233606540c2d75d9250980baeac", SIGNATURE)
        assertEquals("988c5979cc92eee7358005cdac6b369fe3c920e002a1a87c5ed8d3d3b2aed75f", joined)
    }

    @Test
    fun `AC-04 concurrent saves of different layouts all survive`() = runBlocking {
        val store = openStore()
        val repository = ImportProfileRepository(store)
        val profiles = (0 until CONTENDERS).associate { index ->
            ImportProfileRepository.signature(listOf("Date $index", "Amount"), ',') to
                ImportProfile(
                    mapping = CsvColumnMapping(date = "Date $index", amount = "Amount", note = "Note $index"),
                    categorySelections = mapOf("Row $index" to "id-$index"),
                )
        }

        profiles.map { (signature, profile) ->
            async(Dispatchers.Default) { repository.save(profile, signature) }
        }.awaitAll()

        // Every committed layout is observable — the check that fails if the read-modify-write
        // leaks outside DataStore's `edit` transform and saves clobber each other.
        assertEquals(profiles, repository.profiles.first())
        assertEquals(profiles, ImportProfileRepository(restart()).profiles.first())
    }

    @Test
    fun `AC-05 an unreadable layout is skipped on its own and the rest stay readable`() = runBlocking {
        val store = openStore()
        val repository = ImportProfileRepository(store)
        val good = ImportProfile(mapping = CsvColumnMapping(date = "Date", amount = "Amount"))
        repository.save(good, SIGNATURE)

        // One entry from a build whose mapping shape this one cannot read.
        val blob = JSONObject(requireNotNull(store.data.first()[ImportProfileRepository.Keys.importProfiles]))
        blob.put("broken-signature", JSONObject().put("mapping", JSONObject().put("amount", "Amount")))
        store.edit { it[ImportProfileRepository.Keys.importProfiles] = blob.toString() }

        assertEquals(mapOf(SIGNATURE to good), repository.profiles.first())
        // Reading does not repair by rewriting: the unreadable entry is still on disk.
        assertTrue(
            requireNotNull(store.data.first()[ImportProfileRepository.Keys.importProfiles])
                .contains("broken-signature"),
        )
    }

    @Test
    fun `AC-05 an unknown sign convention falls back without losing the rest of the mapping`() = runBlocking {
        val store = openStore()
        val repository = ImportProfileRepository(store)
        repository.save(
            ImportProfile(mapping = CsvColumnMapping(date = "Date", amount = "Amount", note = "Note")),
            SIGNATURE,
        )

        val blob = JSONObject(requireNotNull(store.data.first()[ImportProfileRepository.Keys.importProfiles]))
        blob.getJSONObject(SIGNATURE).getJSONObject("mapping").put("signConvention", "ROUND_TRIP")
        store.edit { it[ImportProfileRepository.Keys.importProfiles] = blob.toString() }

        val recovered = requireNotNull(repository.profile(SIGNATURE))
        assertEquals(SignConvention.SIGNED, recovered.mapping.signConvention)
        assertEquals("Date", recovered.mapping.date)
        assertEquals("Amount", recovered.mapping.amount)
        assertEquals("Note", recovered.mapping.note)
    }

    @Test
    fun `AC-05 a corrupt blob yields no profiles and leaves unrelated preferences alone`() = runBlocking {
        val store = openStore()
        val preferences = UserPreferencesRepository(store)
        val importProfiles = ImportProfileRepository(store)
        preferences.setBaseCurrency("DKK")
        preferences.setUserFullName("Radia Perlman")

        store.edit { it[ImportProfileRepository.Keys.importProfiles] = "{not json at all" }

        assertEquals(emptyMap<String, ImportProfile>(), importProfiles.profiles.first())
        assertEquals("DKK", preferences.baseCurrency.first())
        assertEquals("Radia Perlman", preferences.userFullName.first())

        // And a later save recovers cleanly rather than staying stuck.
        val profile = ImportProfile(mapping = CsvColumnMapping(date = "Date", amount = "Amount"))
        importProfiles.save(profile, SIGNATURE)
        assertEquals(mapOf(SIGNATURE to profile), importProfiles.profiles.first())
        assertEquals("DKK", preferences.baseCurrency.first())
    }

    private fun openStore(): DataStore<Preferences> = StoreSession(file).also { session = it }.store

    private suspend fun restart(): DataStore<Preferences> {
        requireNotNull(session).close()
        return openStore()
    }

    private class StoreSession(file: File) {
        private val job = SupervisorJob()
        private val scope = CoroutineScope(Dispatchers.IO + job)
        val store: DataStore<Preferences> = PreferenceDataStoreFactory.create(scope = scope) { file }

        suspend fun close() = job.cancelAndJoin()
    }

    private companion object {
        const val CONTENDERS = 40
        val SIGNATURE = ImportProfileRepository.signature(listOf("Date", "Amount", "Note"), ';')
    }
}
